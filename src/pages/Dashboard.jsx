import React, { useState } from "react";
import { useNavigate } from "react-router-dom";

export default function Dashboard() {
  const [activeSection, setActiveSection] = useState("Overview");
  const navigate = useNavigate();

  const sections = ["Overview", "Claims", "AI Report", "History"];

  return (
    <div style={{ display: "flex", minHeight: "100vh", background: "#f7f7f7" }}>
      {/* Sidebar */}
      <aside style={{
        width: 220,
        background: "#fff",
        borderRight: "1px solid #eee",
        padding: "24px 0",
        display: "flex",
        flexDirection: "column",
        gap: 8
      }}>
        <div style={{ fontWeight: 800, color: "#ff8a00", fontSize: 22, padding: "0 24px 24px" }}>
          TPL <span style={{ color: "#222" }}>Claims</span>
        </div>
        <nav style={{ flex: 1 }}>
          <ul style={{ listStyle: "none", padding: 0, margin: 0 }}>
            {sections.map((section) => (
              <li
                key={section}
                onClick={() => setActiveSection(section)}
                style={{
                  background: activeSection === section ? "#ffe3c1" : "transparent",
                  fontWeight: activeSection === section ? 700 : 400,
                  color: activeSection === section ? "#ff8a00" : "#222",
                  borderRadius: 8,
                  margin: "0 12px",
                  padding: "10px 18px",
                  cursor: "pointer"
                }}
              >
                {section}
              </li>
            ))}
          </ul>
        </nav>
        <div style={{ marginTop: "auto", padding: "0 24px" }}>
          <div style={{ color: "#888", fontSize: 14, marginBottom: 8 }}>Settings</div>
          <button
            onClick={() => navigate("/")}
            style={{
              width: "100%",
              background: "#fff",
              border: "1px solid #eee",
              borderRadius: 8,
              padding: "8px 0",
              color: "#ff8a00",
              fontWeight: 600,
              cursor: "pointer"
            }}>Logout</button>
        </div>
      </aside>

      {/* Main Content */}
      <main style={{ flex: 1, padding: "32px 32px 0 32px" }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <div>
            <div style={{ fontWeight: 700, fontSize: 20 }}>Welcome back, Claims Manager!</div>
            <div style={{ color: "#888", fontSize: 15 }}>Have a great day managing claims!</div>
          </div>
          <div style={{
            width: 40, height: 40, borderRadius: "50%",
            background: "#ffe3c1", color: "#ff8a00",
            display: "flex", alignItems: "center", justifyContent: "center",
            fontWeight: 700, fontSize: 20
          }}>CM</div>
        </div>

        {/* Profile Card */}
        <div style={{
          background: "linear-gradient(90deg, #ffb366 0%, #ff8a00 100%)",
          borderRadius: 16,
          padding: 24,
          margin: "32px 0 20px 0",
          color: "#fff",
          display: "flex",
          alignItems: "center",
          gap: 24
        }}>
          <div style={{
            width: 60, height: 60, borderRadius: "50%",
            background: "#fff", color: "#ff8a00",
            display: "flex", alignItems: "center", justifyContent: "center",
            fontWeight: 700, fontSize: 28
          }}>BA</div>
          <div>
            <div style={{ fontWeight: 700, fontSize: 22 }}>Beena Ahmed <span style={{
              background: "#fff",
              color: "#ff8a00",
              borderRadius: 6,
              fontSize: 13,
              fontWeight: 600,
              padding: "2px 8px",
              marginLeft: 8
            }}>General</span></div>
            <div style={{ fontSize: 15 }}>Employee</div>
            <div style={{ fontSize: 14, opacity: 0.9 }}>✉ beena.ahmed1811@gmail.com</div>
          </div>
        </div>

        {/* Stats */}
        <div style={{ display: "flex", gap: 20, marginBottom: 24 }}>
          <div style={{
            flex: 1,
            background: "#fff",
            borderRadius: 12,
            padding: 18,
            textAlign: "center",
            fontWeight: 600
          }}>
            <div style={{ color: "#888", fontSize: 14 }}>Total Claims Submitted</div>
            <div style={{ fontSize: 22, fontWeight: 700 }}>3</div>
            <div style={{ color: "#aaa", fontSize: 13 }}>Today</div>
          </div>
          <div style={{
            flex: 1,
            background: "#fff",
            borderRadius: 12,
            padding: 18,
            textAlign: "center",
            fontWeight: 600
          }}>
            <div style={{ color: "#888", fontSize: 14 }}>Top Damaged Part</div>
            <div style={{ fontSize: 20, fontWeight: 700 }}>damaged_bumper</div>
            <div style={{ color: "#aaa", fontSize: 13 }}>Across Today's claims</div>
          </div>
          <div style={{
            flex: 1,
            background: "#fff",
            borderRadius: 12,
            padding: 18,
            textAlign: "center",
            fontWeight: 600
          }}>
            <div style={{ color: "#888", fontSize: 14 }}>Top Severity</div>
            <div style={{ fontSize: 20, fontWeight: 700 }}>Moderate</div>
            <div style={{ color: "#aaa", fontSize: 13 }}>Today</div>
          </div>
          <div style={{
            flex: 1,
            background: "#fff",
            borderRadius: 12,
            padding: 18,
            textAlign: "center",
            fontWeight: 600
          }}>
            <div style={{ color: "#888", fontSize: 14 }}>Estimated Repair Cost</div>
            <div style={{ fontSize: 20, fontWeight: 700 }}>Rs 333,790</div>
            <div style={{ color: "#aaa", fontSize: 13 }}>Today</div>
          </div>
        </div>

        {/* Charts/Lists */}
        <div style={{ display: "flex", gap: 20 }}>
          <div style={{
            flex: 1,
            background: "#fff",
            borderRadius: 12,
            padding: 18
          }}>
            <div style={{ fontWeight: 700, marginBottom: 10 }}>Top 5 Most Claimed Models</div>
            <div>
              <div>Suzuki Cultus <div style={{ background: "#ffb366", height: 14, width: "80%", borderRadius: 7, margin: "4px 0" }} /></div>
              <div>Toyota Corolla <div style={{ background: "#ffb366", height: 14, width: "65%", borderRadius: 7, margin: "4px 0" }} /></div>
              <div>Toyota Corolla XLI/GLI <div style={{ background: "#ffb366", height: 14, width: "55%", borderRadius: 7, margin: "4px 0" }} /></div>
              <div>Honda Civic <div style={{ background: "#ffb366", height: 14, width: "40%", borderRadius: 7, margin: "4px 0" }} /></div>
            </div>
          </div>
          <div style={{
            flex: 1,
            background: "#fff",
            borderRadius: 12,
            padding: 18
          }}>
            <div style={{ fontWeight: 700, marginBottom: 10 }}>Repair Cost Timeline (Daywise - Top 3 Models)</div>
            {/* Placeholder for chart */}
            <svg width="100%" height="120" viewBox="0 0 220 120">
              <polyline points="0,100 40,60 80,80 120,40 160,60 200,20" fill="none" stroke="#ff8a00" strokeWidth="3"/>
              <polyline points="0,80 40,90 80,60 120,80 160,40 200,60" fill="none" stroke="#bdbdbd" strokeWidth="3"/>
              <polyline points="0,60 40,40 80,50 120,60 160,20 200,40" fill="none" stroke="#6ec6ff" strokeWidth="3"/>
            </svg>
          </div>
        </div>
      </main>
    </div>
  );
}