import React from 'react';
import { motion } from 'framer-motion';
import { ShieldCheck, Brain, Layers, Cpu, GitBranch, Users, Zap, Database } from 'lucide-react';
import Navbar from './Navbar';

const fadeUp = {
  hidden: { opacity: 0, y: 30 },
  visible: (i = 0) => ({
    opacity: 1,
    y: 0,
    transition: { duration: 0.7, delay: i * 0.1, ease: [0.16, 1, 0.3, 1] },
  }),
};

const stats = [
  { label: 'Training Images', value: '10,000+', icon: <Database size={20} /> },
  { label: 'Training Videos', value: '2,000+', icon: <Layers size={20} /> },
  { label: 'Model Accuracy', value: '93.84%', icon: <ShieldCheck size={20} /> },
  { label: 'Detection Speed', value: '< 2s', icon: <Zap size={20} /> },
];

const pipeline = [
  {
    icon: <Database size={24} />,
    title: 'Dataset Synthesis',
    desc: 'A balanced training set of 10,000 images and 2,000 videos was synthesized using Gaussian blur, noise injection, and temporal shifts to create realistic fake samples for robust generalization.',
  },
  {
    icon: <Brain size={24} />,
    title: 'Image Model (CNN)',
    desc: 'A EfficientNet-based Convolutional Neural Network was trained with Early Stopping and ReduceLROnPlateau scheduling to classify images as Real or AI-generated with 93.84% validation accuracy.',
  },
  {
    icon: <GitBranch size={24} />,
    title: 'Video Model (CNN-LSTM)',
    desc: 'A hybrid CNN-LSTM architecture processes temporal frame sequences, detecting deepfake artifacts like unnatural blinking, expression inconsistencies, and inter-frame noise anomalies.',
  },
  {
    icon: <Cpu size={24} />,
    title: 'FastAPI Backend',
    desc: 'The trained PyTorch models are served via a FastAPI inference server, accepting image and video uploads and returning prediction results with confidence scores in real-time.',
  },
];

const team = [
  { name: 'DIVS Research Team', role: 'Architecture & Training', initials: 'DR' },
  { name: 'Neural Pipeline', role: 'Dataset Engineering', initials: 'NP' },
  { name: 'FYP Lab', role: 'Evaluation & Testing', initials: 'FL' },
];

export default function About({ onNavigate }) {
  return (
    <div className="min-h-screen bg-[#0a0a0f] text-white relative overflow-hidden">
      {/* Grid background */}
      <div className="absolute inset-0 z-0 opacity-10" style={{
        backgroundSize: '40px 40px',
        backgroundImage: 'linear-gradient(to right, #ffffff11 1px, transparent 1px), linear-gradient(to bottom, #ffffff11 1px, transparent 1px)',
      }} />
      {/* Radial glow */}
      <div className="absolute top-0 left-1/2 -translate-x-1/2 w-[600px] h-[400px] bg-indigo-600/10 rounded-full blur-[120px] pointer-events-none" />

      <Navbar currentView="ABOUT" onNavigate={onNavigate} />

      <main className="relative z-10 max-w-6xl mx-auto px-6 md:px-12 pt-32 pb-20">

        {/* Hero */}
        <motion.div variants={fadeUp} initial="hidden" animate="visible" className="text-center mb-20">
          <p className="text-xs font-bold tracking-[0.3em] text-indigo-400 mb-4">ABOUT THE SYSTEM</p>
          <h1 className="text-5xl md:text-7xl font-playfair italic mb-6 leading-tight">
            The Science of<br />
            <span className="bg-gradient-to-r from-indigo-400 to-purple-400 bg-clip-text text-transparent">Seeing Truth</span>
          </h1>
          <p className="text-white/60 max-w-2xl mx-auto text-base md:text-lg leading-relaxed">
            DIVS is a deepfake detection system built as part of a Final Year Project, combining state-of-the-art deep learning with a premium, real-time user interface.
          </p>
        </motion.div>

        {/* Stats Grid */}
        <motion.div
          initial="hidden" animate="visible"
          variants={{ visible: { transition: { staggerChildren: 0.08 } } }}
          className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-24"
        >
          {stats.map((s, i) => (
            <motion.div key={i} custom={i} variants={fadeUp}
              className="p-6 rounded-2xl border border-white/5 bg-white/[0.03] backdrop-blur-md hover:border-indigo-500/40 hover:bg-indigo-500/5 transition-all group"
            >
              <div className="text-indigo-400 mb-3 group-hover:scale-110 transition-transform">{s.icon}</div>
              <div className="text-3xl font-bold font-mono mb-1">{s.value}</div>
              <div className="text-xs text-white/50 tracking-widest uppercase">{s.label}</div>
            </motion.div>
          ))}
        </motion.div>

        {/* Pipeline */}
        <motion.div variants={fadeUp} custom={2} initial="hidden" animate="visible" className="mb-24">
          <p className="text-xs font-bold tracking-[0.3em] text-indigo-400 mb-4 text-center">HOW IT WORKS</p>
          <h2 className="text-3xl md:text-4xl font-playfair italic text-center mb-12">The Detection Pipeline</h2>
          <div className="grid md:grid-cols-2 gap-6">
            {pipeline.map((step, i) => (
              <motion.div key={i} custom={i + 3} variants={fadeUp} initial="hidden" animate="visible"
                className="p-8 rounded-2xl border border-white/5 bg-white/[0.03] backdrop-blur-md hover:border-indigo-500/40 transition-all group"
              >
                <div className="w-12 h-12 rounded-xl bg-indigo-500/10 border border-indigo-500/20 flex items-center justify-center text-indigo-400 mb-5 group-hover:scale-110 group-hover:bg-indigo-500/20 transition-all">
                  {step.icon}
                </div>
                <h3 className="text-lg font-bold mb-3">{step.title}</h3>
                <p className="text-white/60 text-sm leading-relaxed">{step.desc}</p>
              </motion.div>
            ))}
          </div>
        </motion.div>

        {/* Tech Stack */}
        <motion.div variants={fadeUp} custom={6} initial="hidden" animate="visible" className="mb-24">
          <p className="text-xs font-bold tracking-[0.3em] text-indigo-400 mb-4 text-center">BUILT WITH</p>
          <h2 className="text-3xl md:text-4xl font-playfair italic text-center mb-12">Technology Stack</h2>
          <div className="flex flex-wrap gap-3 justify-center">
            {['PyTorch', 'EfficientNet', 'CNN-LSTM', 'FastAPI', 'React 19', 'Vite', 'Tailwind CSS', 'Framer Motion', 'OpenCV', 'NumPy', 'Styled Components', 'Axios'].map((tech, i) => (
              <motion.span key={i} custom={i} variants={fadeUp} initial="hidden" animate="visible"
                className="px-4 py-2 rounded-full text-sm font-medium border border-white/10 bg-white/[0.04] hover:border-indigo-500/50 hover:text-indigo-300 transition-all cursor-default"
              >
                {tech}
              </motion.span>
            ))}
          </div>
        </motion.div>

        {/* Team Section */}
        <motion.div variants={fadeUp} custom={7} initial="hidden" animate="visible" className="mb-24 flex flex-col items-center">
          <p className="text-xs font-bold tracking-[0.3em] text-indigo-400 mb-4 text-center">THE ARCHITECTS</p>
          <h2 className="text-3xl md:text-4xl font-playfair italic text-center mb-4">Project Team</h2>
          <p className="text-white/60 mb-16 text-center max-w-lg">The core developers and researchers behind the DIVS Deepfake Detection System.</p>
          
          <TeamCards />
          
          <div className="flex gap-12 mt-16 text-center">
            <div>
              <h3 className="font-bold text-lg text-white">Somana</h3>
              <p className="text-xs text-indigo-400 tracking-widest mt-1 uppercase">Lead Developer</p>
            </div>
            <div>
              <h3 className="font-bold text-lg text-white">Faiza</h3>
              <p className="text-xs text-purple-400 tracking-widest mt-1 uppercase">ML Engineer</p>
            </div>
            <div>
              <h3 className="font-bold text-lg text-white">Anosha</h3>
              <p className="text-xs text-cyan-400 tracking-widest mt-1 uppercase">System Architect</p>
            </div>
          </div>
        </motion.div>

        {/* CTA */}
        <motion.div variants={fadeUp} custom={8} initial="hidden" animate="visible"
          className="text-center p-12 rounded-3xl border border-indigo-500/20 bg-indigo-500/5 backdrop-blur-md"
        >
          <h2 className="text-3xl md:text-4xl font-playfair italic mb-4">Ready to analyze media?</h2>
          <p className="text-white/60 mb-8 max-w-md mx-auto">Upload an image or video and let the neural network determine its authenticity in seconds.</p>
          <div className="flex gap-4 justify-center flex-wrap">
            <button
              onClick={() => onNavigate('IMAGE DETECTION')}
              className="px-8 py-3 bg-white text-black font-bold rounded-full hover:bg-gray-100 transition-all hover:shadow-[0_0_30px_rgba(255,255,255,0.3)] uppercase tracking-widest text-sm"
            >
              Image Detection
            </button>
            <button
              onClick={() => onNavigate('VIDEO DETECTION')}
              className="px-8 py-3 bg-indigo-500/20 text-indigo-300 font-bold rounded-full border border-indigo-500/40 hover:bg-indigo-500/30 transition-all uppercase tracking-widest text-sm"
            >
              Video Detection
            </button>
          </div>
        </motion.div>

      </main>
    </div>
  );
}

import styled from 'styled-components';

const TeamCards = () => {
  return (
    <StyledWrapper>
      <div className="wrap_card">
        {/* Somana */}
        <div className="card">
          <div className="content">
            <span>S</span>
            <svg fill="none" viewBox="0 0 24 24" height={48} width={48} className="icon" xmlns="http://www.w3.org/2000/svg">
              <path fill="url(#gradient-full)" d="M12.3999 17.4999C11.8999 17.2999 11.2999 17.3999 11.0999 17.8999L9.29989 21.4999C8.99989 21.9999 9.19989 22.5999 9.69989 22.8999C9.79989 22.9999 9.99989 22.9999 10.1999 22.9999C10.5999 22.9999 10.8999 22.7999 11.0999 22.4999L12.8999 18.8999C13.0999 18.2999 12.8999 17.6999 12.3999 17.4999Z" />
              <path fill="url(#gradient-full)" d="M17 17.4999C16.5 17.2999 15.9 17.3999 15.7 17.8999L13.9 21.4999C13.7 21.9999 13.8 22.5999 14.3 22.7999C14.4 22.8999 14.6 22.8999 14.8 22.8999C15.2 22.8999 15.5 22.6999 15.7 22.3999L17.5 18.7999C17.7 18.2999 17.5 17.6999 17 17.4999Z" />
              <path fill="url(#gradient-full)" d="M7.89994 17.4999C7.39994 17.2999 6.79994 17.3999 6.59994 17.8999L4.79994 21.4999C4.59994 21.9999 4.69994 22.5999 5.19994 22.7999C5.29994 22.9999 5.49994 22.9999 5.59994 22.9999C5.99994 22.9999 6.29994 22.7999 6.49994 22.4999L8.29994 18.8999C8.59994 18.2999 8.39994 17.6999 7.89994 17.4999Z" />
              <path fill="url(#gradient-full)" d="M15.2 1C12.4 1 9.9 2.5 8.5 4.8C8 4.7 7.5 4.6 7 4.6C3.7 4.6 1 7.3 1 10.6C1 13.9 3.7 16.6 7 16.6H15.2C19.5 16.6 23 13.1 23 8.8C23 4.5 19.5 1 15.2 1Z" />
            </svg>
          </div>
        </div>
        {/* Faiza */}
        <div className="card">
          <div className="content">
            <span>F</span>
            <svg fill="none" viewBox="0 0 24 24" height={48} width={48} className="icon" xmlns="http://www.w3.org/2000/svg">
              <path fill="url(#gradient-full)" d="M12.2999 22.0001C9.59992 22.0001 6.99992 21.0001 4.99992 19.0001C0.999923 15.0001 0.999923 8.70009 4.89992 4.80009C6.29992 3.30009 8.19992 2.30009 10.2999 2.00009C10.6999 1.90009 11.0999 2.10009 11.2999 2.50009C11.4999 2.90009 11.4999 3.30009 11.1999 3.60009C8.99992 6.10009 9.19992 10.0001 11.5999 12.4001C13.9999 14.8001 17.7999 15.0001 20.2999 12.8001C20.5999 12.5001 21.0999 12.5001 21.3999 12.7001C21.7999 12.9001 21.9999 13.3001 21.8999 13.7001C21.5999 15.8001 20.5999 17.6001 19.1999 19.1001C17.2999 21.0001 14.7999 22.0001 12.2999 22.0001Z" />
            </svg>
          </div>
        </div>
        {/* Anosha */}
        <div className="card">
          <div className="content">
            <span>A</span>
            <svg fill="none" viewBox="0 0 24 24" height={48} width={48} className="icon" xmlns="http://www.w3.org/2000/svg">
              <path fill="url(#gradient-full)" d="M8.49995 22.9999C8.19995 22.9999 7.89995 22.8999 7.59995 22.7999C6.79995 22.3999 6.39995 21.5999 6.59995 20.7999L7.79995 14.9999H5.99995C5.19995 14.9999 4.49995 14.4999 4.19995 13.7999C3.89995 13.0999 3.99995 12.2999 4.59995 11.7999L14.0999 1.6999C14.6999 1.0999 15.6999 0.899901 16.3999 1.2999C17.1999 1.6999 17.5999 2.4999 17.3999 3.2999L16.1999 9.0999H17.9999C18.7999 9.0999 19.4999 9.5999 19.7999 10.2999C20.0999 10.9999 19.9999 11.7999 19.3999 12.2999L9.89995 22.3999C9.49995 22.7999 8.99995 22.9999 8.49995 22.9999Z" />
            </svg>
          </div>
        </div>
        <svg style={{visibility: 'hidden', width: 0, height: 0, position: 'absolute'}}>
          <defs>
            <linearGradient id="gradient-full" x1="0%" y1="0%" x2="120%" y2="120%">
              <stop offset="0%" stopColor="#ffffff" />
              <stop offset="100%" stopColor="#ffffff00" />
            </linearGradient>
            <linearGradient id="gradient-half" x1="-50%" y1="-50%" x2="100%" y2="100%">
              <stop offset="0%" stopColor="#ffffff" />
              <stop offset="100%" stopColor="#ffffff00" />
            </linearGradient>
          </defs>
        </svg>
        <div className="lines">
          <div className="line" />
          <div className="line" />
        </div>
      </div>
    </StyledWrapper>
  );
}

const StyledWrapper = styled.div`
  .wrap_card {
    position: relative;
    overflow: visible;
    width: var(--w-wrap-card);
    height: calc(var(--h-card) / 1.25);
    display: flex;
    align-items: center;
    justify-content: center;
    --w-card: 150px;
    --h-card: 200px;
    --rotate-card: 15deg;
    --insetX-card: 28px;
    --t-card: calc(var(--insetX-card) * 1.25);
    --w-wrap-card: calc(var(--w-card) + calc(calc(var(--w-card) / 2) * 2));
  }

  .content {
    background-color: rgba(10, 10, 15, 0.7);
    overflow: hidden;
    position: relative;
    width: calc(100% - calc(var(--pd) * 2));
    height: calc(100% - calc(var(--pd) * 2));
    border-radius: calc(var(--round) - var(--pd));
  }
  .content > span {
    font-size: 200px;
    font-weight: 800;
    line-height: 0.75;
    position: absolute;
    width: 100%;
    height: 100%;
    inset: 50% 0 0 50%;
    transform: translate(-50%, -50%);
    background-clip: text;
    -webkit-text-stroke-width: 3px;
    color: transparent;
    opacity: 0;
    background-image: linear-gradient(-45deg, rgba(255,255,255,0.1) 0%, rgba(255,255,255,0.8) 100%);
    animation: opacity 0s cubic-bezier(1, 0, 0, 1) forwards var(--delay) reverse;
  }
  .content > svg {
    height: 66px;
    width: 66px;
    position: absolute;
    inset: 50% 0 0 50%;
    opacity: 1;
    animation: opacity 8.4s cubic-bezier(1, 0, 0, 1) forwards
      calc(var(--delay) - 4.3s);
    transform: translate(-50%, -50%);
  }
  .card:nth-child(1) {
    --delay: 4.3s;
  }
  .card:nth-child(2) {
    --delay: 7.3s;
  }
  .card:nth-child(3) {
    --delay: 10.3s;
  }
  @keyframes opacity {
    from {
      opacity: 1;
    }
    to {
      opacity: 0;
    }
  }

  .card {
    display: flex;
    align-items: center;
    justify-content: center;
    position: absolute;
    overflow: hidden;
    animation: rotating 9s cubic-bezier(0.75, 0, 0, 1.01) infinite 0s;
    border-radius: var(--round);
    background: var(--bg);
    order: var(--order);
    width: var(--w-card);
    height: var(--h-card);
    z-index: var(--z1);
    top: var(--t1);
    left: var(--l1);
    right: var(--r1);
    transform: var(--trans1);
    --pd: 4px;
    --round: 16px;
    --x1: var(--insetX-card);
    --x2: calc(var(--w-wrap-card) - calc(var(--w-card) + var(--insetX-card)));
    --to-left: rotate(calc(var(--rotate-card) * -1));
    --to-center: calc(var(--w-card) / 2);
    --to-right: rotate(calc(var(--rotate-card) * 1));
    box-shadow: 0 0 30px rgba(0,0,0,0.5);
  }

  /* Robotic / Cybernetic Theme Gradients */
  .card:nth-child(1) {
    --order: 2;
    --bg: radial-gradient(circle, #6366f1 0%, #4338ca 40%, #312e81 100%);
    --z1: 2;
    --t1: 0;
    --l1: var(--to-center);
    --r1: var(--to-center);
    --trans1: rotate(calc(var(--rotate-card) * 0));
    --z2: 0;
    --t2: var(--t-card);
    --l2: var(--x1);
    --r2: var(--x2);
    --trans2: var(--to-left);
    --z3: 0;
    --t3: var(--t-card);
    --l3: var(--x2);
    --r3: var(--x1);
    --trans3: var(--to-right);
  }
  .card:nth-child(2) {
    --order: 3;
    --bg: radial-gradient(circle, #a855f7 0%, #7e22ce 40%, #581c87 100%);
    --z1: 0;
    --t1: var(--t-card);
    --l1: var(--x2);
    --r1: var(--x1);
    --trans1: var(--to-right);
    --z2: 2;
    --t2: 0;
    --l2: var(--to-center);
    --r2: var(--to-center);
    --trans2: rotate(calc(var(--rotate-card) * 0));
    --z3: 0;
    --t3: var(--t-card);
    --l3: var(--x1);
    --r3: var(--x2);
    --trans3: var(--to-left);
  }
  .card:nth-child(3) {
    --order: 1;
    --bg: radial-gradient(circle, #06b6d4 0%, #0891b2 40%, #164e63 100%);
    --z1: 0;
    --t1: var(--t-card);
    --l1: var(--x1);
    --r1: var(--x2);
    --trans1: var(--to-left);
    --z2: 0;
    --t2: var(--t-card);
    --l2: var(--x2);
    --r2: var(--x1);
    --trans2: var(--to-right);
    --z3: 2;
    --t3: 0;
    --l3: var(--to-center);
    --r3: var(--to-center);
    --trans3: rotate(calc(var(--rotate-card) * 0));
  }
  
  @keyframes rotating {
    0%,
    99.99% {
      z-index: var(--z1);
      top: var(--t1);
      left: var(--l1);
      right: var(--r1);
      transform: var(--trans1);
    }
    33.33% {
      z-index: var(--z2);
      top: var(--t2);
      left: var(--l2);
      right: var(--r2);
      transform: var(--trans2);
    }
    66.66% {
      z-index: var(--z3);
      top: var(--t3);
      left: var(--l3);
      right: var(--r3);
      transform: var(--trans3);
    }
  }

  .lines {
    position: absolute;
    inset: auto 0 0;
    width: 100%;
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 4;
  }
  .lines::after {
    content: "";
    width: 100%;
    height: 0px;
    position: absolute;
    z-index: 2;
    inset: 0;
    --mask-bg: #0a0a0f;
    background: var(--mask-bg);
    mask-image: radial-gradient(
      50% 200px at top,
      transparent 20%,
      var(--mask-bg)
    );
  }

  .line {
    position: absolute;
    width: 100%;
    display: flex;
    align-items: center;
    justify-content: center;
  }
  .line::before,
  .line::after {
    content: "";
    position: absolute;
    inset: auto;
    background: linear-gradient(
      to right,
      var(--gradient-a-line, #0000),
      var(--gradient-b-line, #0000),
      var(--gradient-c-line, #0000)
    );
    filter: var(--blur-line);
    width: var(--w-line);
    height: var(--h-line);
  }
  .line:nth-child(1)::before {
    --blur-line: blur(4px);
    --w-line: 100%;
    --h-line: 5px;
    --gradient-b-line: #4f46e5;
  }
  .line:nth-child(1)::after {
    --w-line: 100%;
    --h-line: 1px;
    --gradient-b-line: #818cf8;
  }
  .line:nth-child(2)::before {
    --blur-line: blur(4px);
    --w-line: 50%;
    --h-line: 5px;
    --gradient-b-line: #06b6d4;
  }
  .line:nth-child(2)::after {
    --w-line: 50%;
    --h-line: 1px;
    --gradient-b-line: #67e8f9;
  }
`;
