import React, { useRef, useState } from 'react';

import { useFrame, useThree } from '@react-three/fiber';
import { useTexture } from '@react-three/drei';
import * as THREE from 'three';

const Hero3DImage = () => {
  const meshRef = useRef();
  const texture = useTexture('/robo_nobg.png');
  const { viewport, pointer } = useThree();

  // Basic spring animation for smooth movement
  useFrame(() => {
    if (meshRef.current) {
      // Calculate target rotation based on mouse position
      const targetRotationX = (pointer.y * viewport.height) / 10;
      const targetRotationY = (pointer.x * viewport.width) / 10;
      
      // Smoothly interpolate current rotation to target rotation
      meshRef.current.rotation.x = THREE.MathUtils.lerp(meshRef.current.rotation.x, targetRotationX, 0.1);
      meshRef.current.rotation.y = THREE.MathUtils.lerp(meshRef.current.rotation.y, targetRotationY, 0.1);
      
      // Add subtle floating animation
      meshRef.current.position.y = Math.sin(Date.now() / 1000) * 0.2;
    }
  });

  return (
    <mesh ref={meshRef} scale={[3.5, 3.5, 3.5]}>
      <planeGeometry args={[1, 1]} />
      <meshStandardMaterial 
        map={texture} 
        transparent={true} 
        side={THREE.DoubleSide} 
        emissive={new THREE.Color(0x00f0ff)}
        emissiveIntensity={0.1}
      />
    </mesh>
  );
};

export default Hero3DImage;
