// src/firebase.js

import { initializeApp } from "firebase/app";
import { getFirestore } from "firebase/firestore";
import { getAuth } from "firebase/auth";


const firebaseConfig = {
  apiKey: "AIzaSyAjfAasOgyTdJuHOc-IgetTkzAkY_8hyII",
  authDomain: "car-damage-claim-7768a.firebaseapp.com",
  projectId: "car-damage-claim-7768a",
  storageBucket: "car-damage-claim-7768a.firebasestorage.app",
  messagingSenderId: "1031409781145",
  appId: "1:1031409781145:web:ee74a79b028ff84219eb08",
  measurementId: "G-4H9BMFK180",
};

// ✅ Initialize Firebase
const app = initializeApp(firebaseConfig);

// ✅ Initialize Services
export const db = getFirestore(app);
export const auth = getAuth(app);

console.log("🔥 Firebase initialized successfully");
