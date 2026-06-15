import React from "react";

export default function IntelliClaim() {
	return (
		<>
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
		</>
	);
}


