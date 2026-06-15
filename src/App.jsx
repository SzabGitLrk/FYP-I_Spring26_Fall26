import React, { useEffect } from "react";
import { Routes, Route, useLocation } from "react-router-dom";
import "./App.css";

import Navbar from "./components/Navbar";
import Footer from "./components/Footer";
import { ProtectedRoute } from "./components/ProtectedRoute";

import Home from "./pages/Home";
import Plans from "./pages/Plans";
import Quote from "./pages/Quote";
import Claims from "./pages/Claims";
import About from "./pages/About";
import Contact from "./pages/Contact";
import Features from "./pages/Features";
import IntelliClaim from "./pages/IntelliClaim";
import HowItWorks from "./pages/HowItWorks";
import FAQ from "./pages/FAQ";
import LoginSelection from "./pages/LoginSelection";
import AdminLogin from "./pages/AdminLogin";
import UserLogin from "./pages/Login";
import Signup from "./pages/Signup";
import AdminDashboard from "./pages/AdminDashboard";
import UserDashboard from "./pages/UserDashboard";
import Dashboard from "./pages/Dashboard";

import { db } from "./firebase";
import { collection, getDocs } from "firebase/firestore";

function App() {
  const location = useLocation();

  // Hide Navbar & Footer on login/dashboard pages
  const hideNavbar =
    location.pathname === "/login" ||
    location.pathname === "/signup" ||
    location.pathname === "/dashboard" ||
    location.pathname === "/login-selection" ||
    location.pathname === "/admin-login" ||
    location.pathname === "/user-login" ||
    location.pathname === "/admin-dashboard" ||
    location.pathname === "/user-dashboard";

  // ✅ Firebase connection test
  useEffect(() => {
    console.log("App mounted ✅");
    async function testFirebase() {
      try {
        const querySnapshot = await getDocs(collection(db, "test"));
        console.log("✅ Firestore connected!");
        console.log("Documents found:", querySnapshot.size);
      } catch (error) {
        console.error("❌ Firestore error:", error);
      }
    }
    testFirebase();
  }, []);

  return (
    <div className="app-root">
      {!hideNavbar && <Navbar />}
      <main className="app-content">
        <Routes>
          <Route path="/" element={<Home />} />
          <Route path="/features" element={<Features />} />
          <Route path="/intelliclaim" element={<IntelliClaim />} />
          <Route path="/how-it-works" element={<HowItWorks />} />
          <Route path="/faq" element={<FAQ />} />
          <Route path="/plans" element={<Plans />} />
          <Route path="/quote" element={<Quote />} />
          <Route path="/claims" element={<Claims />} />
          <Route path="/about" element={<About />} />
          <Route path="/contact" element={<Contact />} />
          <Route path="/login-selection" element={<LoginSelection />} />
          <Route path="/admin-login" element={<AdminLogin />} />
          <Route path="/user-login" element={<UserLogin />} />
          <Route path="/signup" element={<Signup />} />
          <Route path="/admin-dashboard" element={<ProtectedRoute><AdminDashboard /></ProtectedRoute>} />
          <Route path="/user-dashboard" element={<ProtectedRoute><UserDashboard /></ProtectedRoute>} />
          <Route path="/dashboard" element={<ProtectedRoute><Dashboard /></ProtectedRoute>} />
        </Routes>
      </main>
      {!hideNavbar && <Footer />}
    </div>
  );
}

export default App;
