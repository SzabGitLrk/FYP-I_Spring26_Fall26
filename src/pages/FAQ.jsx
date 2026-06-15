import React, { useState } from "react";

const faqData = [
	{
		question: "How does the AI detect damage?",
		answer:
			"Our AI system uses computer vision and machine learning models trained on millions of vehicle damage images. It identifies the make and model of the vehicle, recognizes damaged components, and assesses the severity of damage by comparing against its extensive database of similar cases.",
	},
	{
		question: "Can I override AI suggestions?",
		answer:
			"Yes, authorized users can override AI suggestions and provide manual input if needed. All overrides are logged for transparency.",
	},
	{
		question: "Is my data safe and private?",
		answer: "All data is encrypted in transit and at rest. Access is role-based and auditable.",
	},
	{
		question: "How accurate is the cost estimation?",
		answer:
			"The AI provides highly accurate cost estimates based on historical data and current market rates, but final costs may vary depending on additional factors.",
	},
	{
		question: "How long does the AI assessment take?",
		answer: "Most AI assessments are completed in under a minute, providing near-instant feedback.",
	},
];

export default function FAQ() {
	const [open, setOpen] = useState(null);

	return (
		<section className="faq-full-bg">
			<div className="faq-inner">
				<h1
					style={{
						textAlign: "center",
						fontWeight: 800,
						fontSize: "2rem", // increased from 1.5rem to 2rem
						margin: "32px 0",
					}}
				>
					Frequently Asked Questions
				</h1>
				<div style={{ maxWidth: 900, margin: "0 auto" }}>
					{faqData.map((item, idx) => (
						<div
							key={item.question}
							style={{
								background: "#fff",
								border: "1px solid #ececec",
								borderRadius: "14px",
								margin: "14px 0",
								padding: "0",
							}}
						>
							<div
								onClick={() => setOpen(open === idx ? null : idx)}
								style={{
									cursor: "pointer",
									fontWeight: 600,
									fontSize: "1rem", // reduced from 1.5rem
									padding: "16px 20px",
									display: "flex",
									alignItems: "center",
									justifyContent: "space-between",
								}}
							>
								<span>{item.question}</span>
								<span style={{ fontSize: "1.1rem" }}>
									{open === idx ? "▲" : "▼"}
								</span>
							</div>
							{open === idx && (
								<div
									style={{
										padding: "0 20px 16px 20px",
										color: "#444",
										fontSize: "0.95rem", // reduced from 1.15rem
									}}
								>
									{item.answer}
								</div>
							)}
						</div>
					))}
				</div>
			</div>
		</section>
	);
}






