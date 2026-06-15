import React, { useState } from "react";


const faqData = [
  {
    question: "How does the AI detect damage?",
    answer:
      "Our AI system uses computer vision and machine learning models trained on millions of vehicle damage images. It identifies the make and model of the vehicle, recognizes damaged components, and assesses the severity of damage by comparing against its extensive database of similar cases."
  },
  {
    question: "Can I override AI suggestions?",
    answer:
      "Yes, authorized users can override AI suggestions and provide manual input if needed. All overrides are logged for transparency."
  },
  {
    question: "Is my data safe and private?",
    answer:
      "All data is encrypted in transit and at rest. Access is role-based and auditable."
  },
  {
    question: "How accurate is the cost estimation?",
    answer:
      "The AI provides highly accurate cost estimates based on historical data and current market rates, but final costs may vary depending on additional factors."
  },
  {
    question: "How long does the AI assessment take?",
    answer:
      "Most AI assessments are completed in under a minute, providing near-instant feedback."
  }
];

const features = [
	{
		key: "smart-upload",
		label: "Smart Upload",
		icon: "📤",
		heading: "Smart Upload",
		text: "Easily upload multiple photos using our drag-and-drop interface or capture images directly through the CRM. Our system automatically detects image quality and prompts for better photos if needed to ensure accurate damage assessment.",
	},
	{
		key: "ai-assessment",
		label: "AI Assessment Engine",
		icon: "🤖",
		heading: "AI Assessment Engine",
		text: "Our advanced AI model recognizes vehicle makes and models, identifies damaged parts, analyzes the severity of damage, and provides detailed cost estimates based on current market rates for parts and labor.",
	},
	{
		key: "document-checklist",
		label: "Document Checklist",
		icon: "📋",
		heading: "Document Checklist",
		text: "Automated document verification ensures all required paperwork is submitted before processing, reducing delays and minimizing manual errors.",
	},
	{
		key: "approval-workflow",
		label: "Approval Workflow",
		icon: "🕒",
		heading: "Approval Workflow",
		text: "Streamlined approval processes with automated routing based on claim amount and type. Managers receive instant notifications for claims requiring review, with the ability to approve, reject, or request additional information in one click.",
	},
	{
		key: "real-time-status",
		label: "Real-Time Claim Status",
		icon: "⏱️",
		heading: "Real-Time Claim Status",
		text: "Track every claim’s progress in real-time with a visual progress indicator. The system provides estimated completion times based on historical data and alerts staff when action is needed to move a claim forward.",
	},
];

export default function Home() {
  const [open, setOpen] = useState(null);
  const [active, setActive] = useState(features[0].key);
  const current = features.find((f) => f.key === active);


  return (
    <>
      {/* HERO INTRO */}
      <section className="hero intro-center">
        <div className="container-full" style={{ textAlign: 'center' }}>
          <h1 className="intro-title">Every claim starts with a photo.<br />That’s why we’re here to <span className="highlight">accelerate your ASSESSMENT</span></h1>
        </div>
      </section>

      {/* WHY INTELLICLAIM (orange band) */}
      <section id="inteliclaim" className="why-band">
        <div className="container">
          <h2 className="why-title">Why IntelliClaim</h2>
          <p className="why-sub">
            Our AI powered damage assessment module transforms how you process claims.
          </p>
          <div className="cards three">
            <div className="card shadow">
              <div style={{ fontSize: 24, marginBottom: 10 }}>⚡</div>
              <div className="card-heading">Speed You Can Count On</div>
              <p className="muted">
                AI reduces claim processing time from days to minutes, getting customers back on the road faster.
              </p>
            </div>
            <div className="card shadow">
              <div style={{ fontSize: 24, marginBottom: 10 }}>🔍</div>
              <div className="card-heading">Smarter Evaluations</div>
              <p className="muted">
                Real-time damage analysis from uploaded images provides accurate assessments with detailed reports.
              </p>
            </div>
            <div className="card shadow">
              <div style={{ fontSize: 24, marginBottom: 10 }}>🔒</div>
              <div className="card-heading">Security First</div>
              <p className="muted">
                Privacy-first design and encrypted processing ensures customer data remains secure at all times.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* HOW IT WORKS */}
      <section id="how" className="section">
        <div className="container">
          <h2 className="section-title" style={{ textAlign: 'center' }}>How It Works</h2>
          <p className="muted" style={{ textAlign: 'center', marginBottom: 24 }}>IntelliClaim simplifies the claims process with just a few steps.</p>
          <ol className="steps-list">
            <li>
              <span className="step-badge">1</span>
              <div>
                <strong>Upload Vehicle Photos</strong>
                <p className="muted">Snap and send from your interface or upload existing images.</p>
              </div>
            </li>
            <li>
              <span className="step-badge">2</span>
              <div>
                <strong>Let AI Analyze</strong>
                <p className="muted">Detects damage, assesses severity, and estimates repair costs instantly.</p>
              </div>
            </li>
            <li>
              <span className="step-badge">3</span>
              <div>
                <strong>Submit & Track</strong>
                <p className="muted">Approvals and progress updated in real time.</p>
              </div>
            </li>
          </ol>
        </div>
      </section>

      {/* FEATURES TABS (dynamic like Features page) */}
      <section id="features" className="features-page">
        <h2 className="features-title">IntelliClaim Features</h2>
        <p className="features-sub">
          Explore the powerful features that make IntelliClaim the most advanced
          claims processing system.
        </p>
        <div className="features-tabs">
          {features.map((f) => (
            <button
              key={f.key}
              className={`features-tab${
                active === f.key ? " active" : ""
              }`}
              onClick={() => setActive(f.key)}
            >
              {f.label}
            </button>
          ))}
        </div>
        <div className="features-content">
          <span className="features-icon">{current.icon}</span>
          <div className="features-text-block">
            <div className="features-heading">{current.heading}</div>
            <p className="features-text">{current.text}</p>
          </div>
        </div>
      </section>

      {/* TESTIMONIALS */}
      <section className="section">
        <div className="container">
          <h2 className="section-title" style={{ textAlign: 'center' }}>What Our Team Says</h2>
          <div className="card testimonial">
            <p className="muted" style={{ marginBottom: 6 }}>“Since implementing IntelliClaim, our processing time decreased by 70% while improving accuracy.”</p>
            <div className="muted">Anita Patel — Regional Director, TPL Insurance</div>
          </div>
        </div>
      </section>

      {/* FAQ */}
      <section id="faq" className="section">
        <div className="container">
          <h2 className="section-title" style={{ textAlign: 'center' }}>Frequently Asked Questions</h2>
          <div className="faq-section" style={{ maxWidth: 820, margin: "40px auto" }}>
            {faqData.map((item, idx) => (
              <div
                key={item.question}
                className="faq-item"
                style={{
                  border: "1px solid #e5e7eb",
                  borderRadius: 10,
                  padding: "10px 14px",
                  marginBottom: 10,
                  background: "#fff"
                }}
              >
                <div
                  onClick={() => setOpen(open === idx ? null : idx)}
                  style={{
                    cursor: "pointer",
                    fontWeight: 600,
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "space-between"
                  }}
                >
                  <span>{item.question}</span>
                  <span>{open === idx ? "▲" : "▼"}</span>
                </div>
                {open === idx && (
                  <div style={{ marginTop: 8, color: "#444", fontWeight: 400 }}>
                    {item.answer}
                  </div>
                )}
              </div>
            ))}
          </div>
        </div>
      </section>


    </>
  )
}
