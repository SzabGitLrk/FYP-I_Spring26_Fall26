import React from 'react'
import { NavLink, Link } from 'react-router-dom'

export default function Navbar() {
  return (
    <header className="navbar">
      <div className="container-full navbar-inner">
        <Link to="/" className="brand">
          <span className="brand-title"><span style={{ color: '#ff8a00' }}>Intelli</span>Claims</span>
        </Link>
        <div className="nav-right">
          <nav className="nav-links">
            <NavLink to="/features" className={({ isActive }) => `nav-link${isActive ? ' active' : ''}`}>Features</NavLink>
            <NavLink to="/intelliclaim" className={({ isActive }) => `nav-link${isActive ? ' active' : ''}`}>IntelliClaim</NavLink>
            <NavLink to="/how-it-works" className={({ isActive }) => `nav-link${isActive ? ' active' : ''}`}>How It Works</NavLink>
            <NavLink to="/faq" className={({ isActive }) => `nav-link${isActive ? ' active' : ''}`}>FAQ</NavLink>
          </nav>
          <NavLink to="/login-selection" className="cta-btn" style={{ background: '#ff8a00', textDecoration: 'none', marginRight: 12 }}>Start a Claim</NavLink>
        </div>
      </div>
    </header>
  )
}


