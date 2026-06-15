import React, { useState } from "react";

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

export default function Features() {
	const [active, setActive] = useState(features[0].key);
	const current = features.find((f) => f.key === active);

	return (
		<div className="features-page">
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
		</div>
	);
}








