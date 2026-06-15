import React from "react";
import { Link } from "react-router-dom";

export default function Footer() {
  return (
    <footer className="footer-main">
      <div className="footer-inner">
        <div className="footer-col">
          <div className="footer-title">TPL Insurance CRM</div>
          <div className="footer-desc">
            An integrated platform for managing insurance policies, processing claims,
            and providing exceptional customer service.
          </div>
          <div className="footer-version">intelliClaim beta v1.0</div>
        </div>
        <div className="footer-col">
          <div className="footer-title">Quick Links</div>
          <ul className="footer-links">
            <li><Link to="/features">Features</Link></li>
            <li><Link to="/intelliclaim">IntelliClaim</Link></li>
            <li><Link to="/how-it-works">How It Works</Link></li>
            <li><Link to="/faq">FAQs</Link></li>
          </ul>
        </div>
        <div className="footer-col">
          <div className="footer-title">Resources</div>
          <ul className="footer-links">
            <li><a href="#">About TPL</a></li>
            <li><a href="#">Privacy Policy</a></li>
            <li><a href="#">TPL Insurance Labs</a></li>
            <li><a href="#">Support</a></li>
          </ul>
        </div>
      </div>
    </footer>
  );
}



