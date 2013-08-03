/*
 Copyright (c) 2012 The VCT Project

  This file is part of VoxelConeTracing and is an implementation of
  "Interactive Indirect Illumination Using Voxel Cone Tracing" by Crassin et al

  VoxelConeTracing is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  VoxelConeTracing is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with VoxelConeTracing.  If not, see <http://www.gnu.org/licenses/>.
*/

/*!
* \author Dominik Lazarek (dominik.lazarek@gmail.com)
* \author Andreas Weinmann (andy.weinmann@gmail.com)
*/

/** 
This shader writes the voxel-colors from the voxel fragment list into the
leaf nodes of the octree. The shader is lauched with one thread per entry of
the voxel fragment list.
Every voxel is read from the voxel fragment list and its position is used
to traverse the octree and find the leaf-node.
*/

#version 420 core

#define NODE_MASK_VALUE 0x3FFFFFFF
#define NODE_MASK_TAG (0x00000001 << 31)
#define NODE_MASK_BRICK (0x00000001 << 30)
#define NODE_NOT_FOUND 0xFFFFFFFF
#define NODE_MASK_BRICK (0x00000001 << 30)

layout(r32ui) uniform readonly uimageBuffer voxelFragList_pos;
layout(r32ui) uniform readonly uimageBuffer voxelFragList_color;
layout(r32ui) uniform readonly uimageBuffer nodePool_next;
layout(r32ui) uniform readonly uimageBuffer nodePool_color;
layout(rgba8) uniform image3D brickPool_color;

uniform uint numLevels;  // Number of levels in the octree
uniform uint voxelGridResolution;

const uint pow2[] = {1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024};

const uvec3 childOffsets[8] = {
  uvec3(0, 0, 0),
  uvec3(1, 0, 0),
  uvec3(0, 1, 0),
  uvec3(1, 1, 0),
  uvec3(0, 0, 1),
  uvec3(1, 0, 1),
  uvec3(0, 1, 1), 
  uvec3(1, 1, 1)};

vec4 convRGBA8ToVec4(uint val) {
    return vec4( float((val & 0x000000FF)), 
                 float((val & 0x0000FF00) >> 8U), 
                 float((val & 0x00FF0000) >> 16U), 
                 float((val & 0xFF000000) >> 24U));
}

uint convVec4ToRGBA8(vec4 val) {
    return (uint(val.w) & 0x000000FF)   << 24U
            |(uint(val.z) & 0x000000FF) << 16U
            |(uint(val.y) & 0x000000FF) << 8U 
            |(uint(val.x) & 0x000000FF);
}

uint vec3ToUintXYZ10(uvec3 val) {
    return (uint(val.z) & 0x000003FF)   << 20U
            |(uint(val.y) & 0x000003FF) << 10U 
            |(uint(val.x) & 0x000003FF);
}

uvec3 uintXYZ10ToVec3(uint val) {
    return uvec3(uint((val & 0x000003FF)),
                 uint((val & 0x000FFC00) >> 10U), 
                 uint((val & 0x3FF00000) >> 20U));
}


void traverseToLeaf(in vec3 posTex, in uint voxelColorU) {
  uint nodeAddress = 0;
  vec3 nodePosTex = vec3(0.0);
  vec3 nodePosMaxTex = vec3(1.0);
  float sideLength = 0.5;
  
  
  for (uint iLevel = 0; iLevel < numLevels; ++iLevel) {
    uint nodeNext = imageLoad(nodePool_next, int(nodeAddress)).x;

    uint childStartAddress = nodeNext & NODE_MASK_VALUE;
    if (childStartAddress == 0U) {
      if (iLevel == numLevels - 1) {  // This is a leaf node! Yuppieee! ;)
          // calculate the child index and return
          uvec3 offVec = uvec3(2.0 * posTex);
          uint childIndex = offVec.x + 2U * offVec.y + 4U * offVec.z;

          ivec3 brickCoords = ivec3(uintXYZ10ToVec3(imageLoad(nodePool_color, int(nodeAddress)).x));
          memoryBarrier();

          //store VoxelColors in brick corners
          imageStore(brickPool_color,
                     brickCoords + 2 * ivec3(childOffsets[childIndex]),
                     convRGBA8ToVec4(voxelColorU) / 255.0);
       }
       break;
    }
     
    uvec3 offVec = uvec3(2.0 * posTex);
    uint off = offVec.x + 2U * offVec.y + 4U * offVec.z;

    // Restart while-loop with the child node (aka recursion)
    nodeAddress = childStartAddress + off;
    nodePosTex += vec3(childOffsets[off]) * vec3(sideLength);
    nodePosMaxTex = nodePosTex + vec3(sideLength);

    sideLength = sideLength / 2.0;
    posTex = 2.0 * posTex - vec3(offVec);
  } // level-for

}

void main() {
  // Get the voxel's position and color from the voxel frag list.
  uint voxelPosU = imageLoad(voxelFragList_pos, gl_VertexID).x;
  uint voxelColorU = imageLoad(voxelFragList_color, gl_VertexID).x;

  uvec3 voxelPos = uintXYZ10ToVec3(voxelPosU);
  vec3 posTex = vec3(voxelPos) / vec3(voxelGridResolution);

  traverseToLeaf(posTex, voxelColorU);
  
}
