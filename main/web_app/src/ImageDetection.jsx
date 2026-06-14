import React, { useState, useRef, useEffect } from 'react';
import styled from 'styled-components';
import { Upload, ShieldCheck, ShieldAlert, Loader2, ArrowLeft, Image as ImageIcon } from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';
import axios from 'axios';

import Navbar from './Navbar';

const ImageDetection = ({ onNavigate }) => {
  const [file, setFile] = useState(null);
  const [preview, setPreview] = useState('');
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState(null);
  const [isDragging, setIsDragging] = useState(false);
  const fileInputRef = useRef(null);

  const handleFile = (selected) => {
    if (selected && selected.type.startsWith('image/')) {
      setFile(selected);
      setPreview(URL.createObjectURL(selected));
      setResult(null);
    }
  };

  const handleFileChange = (e) => handleFile(e.target.files[0]);

  useEffect(() => {
    const handlePaste = (e) => {
      const items = e.clipboardData?.items;
      if (!items) return;
      for (let i = 0; i < items.length; i++) {
        if (items[i].type.startsWith('image/')) {
          handleFile(items[i].getAsFile());
          break;
        }
      }
    };
    
    const handleDragOver = (e) => {
      e.preventDefault();
      setIsDragging(true);
    };
    
    const handleDragLeave = (e) => {
      e.preventDefault();
      setIsDragging(false);
    };
    
    const handleDrop = (e) => {
      e.preventDefault();
      setIsDragging(false);
      if (e.dataTransfer.files && e.dataTransfer.files.length > 0) {
        handleFile(e.dataTransfer.files[0]);
      }
    };

    window.addEventListener('paste', handlePaste);
    window.addEventListener('dragover', handleDragOver);
    window.addEventListener('dragleave', handleDragLeave);
    window.addEventListener('drop', handleDrop);
    
    return () => {
      window.removeEventListener('paste', handlePaste);
      window.removeEventListener('dragover', handleDragOver);
      window.removeEventListener('dragleave', handleDragLeave);
      window.removeEventListener('drop', handleDrop);
    };
  }, []);

  const handleReset = () => {
    setFile(null);
    setPreview('');
    setResult(null);
    if (fileInputRef.current) fileInputRef.current.value = '';
  };

  const handleScan = async () => {
    if (!file) return;
    setLoading(true);
    setResult(null);
    const formData = new FormData();
    formData.append('file', file);
    
    try {
      const res = await axios.post(`http://localhost:8000/predict/image`, formData, {
        headers: { 'Content-Type': 'multipart/form-data' },
      });
      // Add artificial delay so user can appreciate the animation
      setTimeout(() => { 
        setResult(res.data); 
        setLoading(false); 
      }, 2500);
    } catch {
      setLoading(false);
      alert('Error connecting to the backend scanner. Make sure app.py is running.');
    }
  };

  return (
    <div className="min-h-screen bg-[#0a0a0f] text-white pt-24 pb-12 px-6 md:px-12 relative overflow-hidden flex flex-col font-inter">
      {/* Grid background */}
      <div className="absolute inset-0 z-0 opacity-10" style={{
        backgroundSize: '40px 40px',
        backgroundImage: 'linear-gradient(to right, #ffffff11 1px, transparent 1px), linear-gradient(to bottom, #ffffff11 1px, transparent 1px)',
      }} />

      <Navbar currentView="IMAGE DETECTION" onNavigate={onNavigate} />

      {/* Main Content */}
      <main className="relative z-10 flex flex-col lg:flex-row flex-1 gap-12 lg:gap-24 items-center justify-center max-w-7xl mx-auto w-full">
        
        {/* Left Section: Cyber Card */}
        <section className="flex-1 flex justify-center items-center w-full">
          <StyledWrapper $isAnalyzing={loading} $hasImage={!!preview}>
            <div 
              className={`container noselect ${isDragging ? 'scale-105' : ''}`}
              onClick={() => {
                if (!loading && !result) {
                  fileInputRef.current?.click();
                }
              }}
              style={{ transition: 'transform 0.2s ease-in-out' }}
            >
              {isDragging && (
                <div className="absolute -inset-4 border-2 border-dashed border-indigo-500 rounded-3xl z-[300] bg-indigo-500/10 pointer-events-none" />
              )}
              <div className="canvas">
                {/* 25 Trackers for 3D tilt effect */}
                {[...Array(25)].map((_, i) => (
                  <div key={i} className={`tracker tr-${i + 1}`} />
                ))}
                
                <div id="card">
                  <div className="card-content">
                    <div className="card-glare" />
                    <div className="cyber-lines">
                      <span /><span /><span /><span />
                    </div>
                    
                    {/* Dynamic Card Content */}
                    <div className="absolute inset-0 flex flex-col items-center justify-center p-4 z-20">
                      {!preview ? (
                        <div className="flex flex-col items-center gap-4 cursor-pointer group">
                          <div className={`w-16 h-16 rounded-full flex items-center justify-center transition-transform ${isDragging ? 'bg-indigo-500/40 border-indigo-400 scale-125' : 'bg-indigo-500/20 border-indigo-500/50 group-hover:scale-110'} border shadow-[0_0_15px_rgba(99,102,241,0.5)]`}>
                            <Upload className="text-indigo-400" size={28} />
                          </div>
                          <p id="prompt">{isDragging ? 'DROP IMAGE HERE' : 'UPLOAD IMAGE'}</p>
                        </div>
                      ) : (
                        <div className="relative w-full h-full flex items-center justify-center group overflow-hidden rounded-xl">
                           <img 
                             src={preview} 
                             alt="Preview" 
                             className={`max-w-full max-h-[180px] object-contain transition-all duration-500 ${loading ? 'opacity-50 blur-sm scale-105' : 'opacity-100'}`} 
                           />
                           
                           {/* Hover overlay to change image */}
                           {!loading && !result && (
                             <div className="absolute inset-0 bg-black/60 opacity-0 group-hover:opacity-100 flex items-center justify-center transition-opacity cursor-pointer backdrop-blur-sm">
                               <span className="text-xs tracking-widest font-bold text-white bg-indigo-600/80 px-4 py-2 rounded">CHANGE IMAGE</span>
                             </div>
                           )}

                           {/* Analyzing State Overlay */}
                           {loading && (
                             <div className="absolute inset-0 flex items-center justify-center flex-col gap-3">
                               <Loader2 className="animate-spin text-[#00ffaa]" size={36} />
                               <span className="text-xs font-bold tracking-[3px] text-[#00ffaa] animate-pulse">ANALYZING</span>
                             </div>
                           )}
                        </div>
                      )}
                    </div>

                    {/* <div className="title">DEEP<br />SCAN</div> */}
                    
                    <div className="glowing-elements">
                      <div className="glow-1" />
                      <div className="glow-2" />
                      <div className="glow-3" />
                    </div>
                    
                    <div className="subtitle">
                      <span>{loading ? 'PROCESSING' : result ? 'ANALYSIS' : preview ? 'READY FOR' : 'AWAITING'}</span>
                      <span className="highlight">{loading ? 'DATA...' : result ? 'COMPLETE' : preview ? 'ANALYSIS' : 'INPUT'}</span>
                    </div>
                    
                    <div className="card-particles">
                      <span /><span /><span /> <span /><span /><span />
                    </div>
                    
                    <div className="corner-elements">
                      <span /><span /><span /><span />
                    </div>
                    
                    {/* Scanning laser line - only active during loading */}
                    <div className={`scan-line ${loading ? 'opacity-100' : 'opacity-0'}`} />
                  </div>
                </div>
              </div>
            </div>
          </StyledWrapper>
          <input type="file" accept="image/*" className="hidden" ref={fileInputRef} onChange={handleFileChange} />
        </section>

        {/* Right Section: Details & Results */}
        <section className="flex-1 w-full flex flex-col justify-center">
          <div className="max-w-md">
            <h1 className="text-4xl md:text-5xl font-playfair italic mb-6 leading-tight">
              Uncover the truth behind the pixels.
            </h1>
            <p className="text-white/60 mb-10 leading-relaxed text-sm md:text-base">
              Upload an image to our advanced neural network. The system analyzes microscopic artifacts, frequency domain anomalies, and pixel inconsistencies to determine if the media is authentic or AI-generated.
            </p>

            <div className="space-y-6">
              {!result ? (
                <button 
                  onClick={handleScan}
                  disabled={!file || loading}
                  className="w-full bg-white text-black py-4 px-8 rounded-full font-bold uppercase tracking-widest text-sm transition-all hover:bg-gray-200 disabled:opacity-50 disabled:cursor-not-allowed hover:shadow-[0_0_30px_rgba(255,255,255,0.3)] disabled:hover:shadow-none"
                >
                  {loading ? 'Executing Neural Scan...' : 'Start Detection'}
                </button>
              ) : (
                <button 
                  onClick={handleReset}
                  className="w-full bg-indigo-500 text-white py-4 px-8 rounded-full font-bold uppercase tracking-widest text-sm transition-all hover:bg-indigo-400 hover:shadow-[0_0_30px_rgba(99,102,241,0.5)]"
                >
                  Test Another Image
                </button>
              )}

              <AnimatePresence mode="wait">
                {result && (
                  <motion.div 
                    initial={{ opacity: 0, y: 20 }} 
                    animate={{ opacity: 1, y: 0 }} 
                    exit={{ opacity: 0, y: -20 }}
                    className={`p-6 rounded-2xl border backdrop-blur-md ${
                      result.prediction === 'Real' 
                        ? 'bg-emerald-500/10 border-emerald-500/30 shadow-[0_0_30px_rgba(16,185,129,0.15)]' 
                        : 'bg-rose-500/10 border-rose-500/30 shadow-[0_0_30px_rgba(244,63,94,0.15)]'
                    }`}
                  >
                    <div className="flex items-start gap-5">
                      <div className={`p-3 rounded-full shrink-0 ${result.prediction === 'Real' ? 'bg-emerald-500/20 text-emerald-400' : 'bg-rose-500/20 text-rose-400'}`}>
                        {result.prediction === 'Real' ? <ShieldCheck size={32} /> : <ShieldAlert size={32} />}
                      </div>
                      <div>
                        <p className="text-xs font-bold tracking-[0.2em] text-white/50 mb-1">ANALYSIS COMPLETE</p>
                        <h3 className={`text-2xl font-bold uppercase mb-2 ${result.prediction === 'Real' ? 'text-emerald-400' : 'text-rose-400'}`}>
                          {result.prediction} Media
                        </h3>
                        <div className="flex items-center gap-2 text-sm text-white/80 bg-black/40 px-3 py-1.5 rounded w-fit border border-white/5">
                          <span className="opacity-70">Confidence Level:</span>
                          <span className="font-bold font-mono">{result.confidence}</span>
                        </div>
                      </div>
                    </div>
                  </motion.div>
                )}
              </AnimatePresence>
            </div>
          </div>
        </section>

      </main>
    </div>
  );
};

// Modified Styled Wrapper to accept props for state-based styling
const StyledWrapper = styled.div`
  .container {
    position: relative;
    width: 320px;
    height: 420px;
    transition: 200ms;
  }

  @media (max-width: 640px) {
    .container {
      width: 260px;
      height: 340px;
    }
  }

  .container:active {
    transform: scale(0.97);
  }

  #card {
    position: absolute;
    inset: 0;
    z-index: 0;
    display: flex;
    justify-content: center;
    align-items: center;
    border-radius: 24px;
    transition: 700ms;
    background: linear-gradient(45deg, #0f172a, #1e1b4b);
    border: 1px solid rgba(99, 102, 241, 0.2);
    overflow: hidden;
    box-shadow:
      0 0 40px rgba(0, 0, 0, 0.5),
      inset 0 0 30px rgba(99, 102, 241, 0.1);
  }

  ${props => props.$isAnalyzing && `
    #card {
      border-color: rgba(0, 255, 170, 0.5);
      box-shadow: 0 0 50px rgba(0, 255, 170, 0.2), inset 0 0 30px rgba(0, 255, 170, 0.1);
    }
    .card-particles span {
      animation: particleFloat 1.5s infinite !important;
    }
    #card::before {
      opacity: 0.8 !important;
    }
    .glowing-elements div {
      opacity: 1 !important;
    }
  `}

  .card-content {
    position: relative;
    width: 100%;
    height: 100%;
  }

  #prompt {
    font-size: 14px;
    font-weight: 600;
    letter-spacing: 3px;
    transition: 300ms ease-in-out;
    text-align: center;
    color: rgba(255, 255, 255, 0.6);
    margin-top: 10px;
  }

  .title {
    opacity: 0;
    transition: 300ms ease-in-out;
    position: absolute;
    top: 20%;
    font-size: 42px;
    font-weight: 900;
    letter-spacing: 6px;
    text-align: center;
    width: 100%;
    background: linear-gradient(45deg, #00ffaa, #00a2ff);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    filter: drop-shadow(0 0 15px rgba(0, 255, 170, 0.3));
    z-index: 30;
    pointer-events: none;
  }

  .subtitle {
    position: absolute;
    bottom: 30px;
    width: 100%;
    text-align: center;
    font-size: 12px;
    letter-spacing: 3px;
    color: rgba(255, 255, 255, 0.5);
    z-index: 30;
  }

  .highlight {
    color: #00ffaa;
    margin-left: 6px;
    background: linear-gradient(90deg, #6366f1, #a855f7);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    font-weight: 800;
  }

  .glowing-elements {
    position: absolute;
    inset: 0;
    pointer-events: none;
    z-index: 10;
  }

  .glow-1, .glow-2, .glow-3 {
    position: absolute;
    width: 120px;
    height: 120px;
    border-radius: 50%;
    background: radial-gradient(circle at center, rgba(0, 255, 170, 0.4) 0%, transparent 70%);
    filter: blur(20px);
    opacity: 0;
    transition: opacity 0.4s ease;
  }

  .glow-1 { top: -30px; left: -30px; }
  .glow-2 { top: 50%; right: -40px; transform: translateY(-50%); background: radial-gradient(circle at center, rgba(99, 102, 241, 0.4) 0%, transparent 70%); }
  .glow-3 { bottom: -30px; left: 20%; }

  .card-particles span {
    position: absolute;
    width: 3px;
    height: 3px;
    background: #00ffaa;
    border-radius: 50%;
    opacity: 0;
    transition: opacity 0.3s ease;
    z-index: 20;
  }

  /* Hover effects only active when NOT analyzing */
  ${props => !props.$isAnalyzing && `
    .tracker:hover ~ #card .title {
      opacity: 1;
      transform: translateY(-10px);
    }
    .tracker:hover ~ #card .glowing-elements div {
      opacity: 1;
    }
    .tracker:hover ~ #card .card-particles span {
      animation: particleFloat 2s infinite;
    }
    .tracker:hover ~ #card::before {
      opacity: 1;
    }
    .tracker:hover ~ #card {
      transition: 300ms;
      filter: brightness(1.2);
    }
  `}

  @keyframes particleFloat {
    0% { transform: translate(0, 0); opacity: 0; }
    50% { opacity: 1; }
    100% { transform: translate(calc(var(--x, 0) * 40px), calc(var(--y, 0) * 40px)); opacity: 0; }
  }

  .card-particles span:nth-child(1) { --x: 1; --y: -1; top: 40%; left: 20%; }
  .card-particles span:nth-child(2) { --x: -1; --y: -1; top: 60%; right: 20%; }
  .card-particles span:nth-child(3) { --x: 0.5; --y: 1; top: 20%; left: 40%; }
  .card-particles span:nth-child(4) { --x: -0.5; --y: 1; top: 80%; right: 40%; }
  .card-particles span:nth-child(5) { --x: 1; --y: 0.5; top: 30%; left: 60%; }
  .card-particles span:nth-child(6) { --x: -1; --y: 0.5; top: 70%; right: 60%; }

  #card::before {
    content: "";
    background: radial-gradient(circle at center, rgba(0, 255, 170, 0.15) 0%, rgba(99, 102, 241, 0.05) 50%, transparent 100%);
    filter: blur(25px);
    opacity: 0;
    width: 150%;
    height: 150%;
    position: absolute;
    left: 50%;
    top: 50%;
    transform: translate(-50%, -50%);
    transition: opacity 0.4s ease;
    z-index: 10;
    pointer-events: none;
  }

  .tracker {
    position: absolute;
    z-index: 200;
    width: 100%;
    height: 100%;
  }

  .tracker:hover { cursor: crosshair; }

  .canvas {
    perspective: 1000px;
    inset: 0;
    z-index: 200;
    position: absolute;
    display: grid;
    grid-template-columns: repeat(5, 1fr);
    grid-template-rows: repeat(5, 1fr);
  }

  /* Grid area definitions for the 25 trackers */
  ${[...Array(25)].map((_, i) => `.tr-${i + 1} { grid-area: tr-${i + 1}; }`).join('\n')}
  
  .canvas {
    grid-template-areas:
      "tr-1 tr-2 tr-3 tr-4 tr-5"
      "tr-6 tr-7 tr-8 tr-9 tr-10"
      "tr-11 tr-12 tr-13 tr-14 tr-15"
      "tr-16 tr-17 tr-18 tr-19 tr-20"
      "tr-21 tr-22 tr-23 tr-24 tr-25";
  }

  /* Complex 3D Rotations based on 5x5 grid hover */
  /* Top row */
  .tr-1:hover ~ #card { transform: rotateX(15deg) rotateY(-15deg); }
  .tr-2:hover ~ #card { transform: rotateX(15deg) rotateY(-7.5deg); }
  .tr-3:hover ~ #card { transform: rotateX(15deg) rotateY(0deg); }
  .tr-4:hover ~ #card { transform: rotateX(15deg) rotateY(7.5deg); }
  .tr-5:hover ~ #card { transform: rotateX(15deg) rotateY(15deg); }
  /* Row 2 */
  .tr-6:hover ~ #card { transform: rotateX(7.5deg) rotateY(-15deg); }
  .tr-7:hover ~ #card { transform: rotateX(7.5deg) rotateY(-7.5deg); }
  .tr-8:hover ~ #card { transform: rotateX(7.5deg) rotateY(0deg); }
  .tr-9:hover ~ #card { transform: rotateX(7.5deg) rotateY(7.5deg); }
  .tr-10:hover ~ #card { transform: rotateX(7.5deg) rotateY(15deg); }
  /* Row 3 (Center) */
  .tr-11:hover ~ #card { transform: rotateX(0deg) rotateY(-15deg); }
  .tr-12:hover ~ #card { transform: rotateX(0deg) rotateY(-7.5deg); }
  .tr-13:hover ~ #card { transform: rotateX(0deg) rotateY(0deg); }
  .tr-14:hover ~ #card { transform: rotateX(0deg) rotateY(7.5deg); }
  .tr-15:hover ~ #card { transform: rotateX(0deg) rotateY(15deg); }
  /* Row 4 */
  .tr-16:hover ~ #card { transform: rotateX(-7.5deg) rotateY(-15deg); }
  .tr-17:hover ~ #card { transform: rotateX(-7.5deg) rotateY(-7.5deg); }
  .tr-18:hover ~ #card { transform: rotateX(-7.5deg) rotateY(0deg); }
  .tr-19:hover ~ #card { transform: rotateX(-7.5deg) rotateY(7.5deg); }
  .tr-20:hover ~ #card { transform: rotateX(-7.5deg) rotateY(15deg); }
  /* Row 5 */
  .tr-21:hover ~ #card { transform: rotateX(-15deg) rotateY(-15deg); }
  .tr-22:hover ~ #card { transform: rotateX(-15deg) rotateY(-7.5deg); }
  .tr-23:hover ~ #card { transform: rotateX(-15deg) rotateY(0deg); }
  .tr-24:hover ~ #card { transform: rotateX(-15deg) rotateY(7.5deg); }
  .tr-25:hover ~ #card { transform: rotateX(-15deg) rotateY(15deg); }

  .noselect {
    user-select: none;
    -webkit-user-drag: none;
  }

  .card-glare {
    position: absolute;
    inset: 0;
    background: linear-gradient(125deg, transparent 0%, rgba(255,255,255,0.03) 45%, rgba(255,255,255,0.1) 50%, rgba(255,255,255,0.03) 55%, transparent 100%);
    opacity: 0;
    transition: opacity 300ms;
    pointer-events: none;
    z-index: 40;
  }

  #card:hover .card-glare { opacity: 1; }

  .cyber-lines span {
    position: absolute;
    background: linear-gradient(90deg, transparent, rgba(99, 102, 241, 0.4), transparent);
    z-index: 10;
    pointer-events: none;
  }

  .cyber-lines span:nth-child(1) { top: 20%; left: 0; w: 100%; h: 1px; transform: scaleX(0); transform-origin: left; animation: lineGrow 3s linear infinite; }
  .cyber-lines span:nth-child(2) { top: 40%; right: 0; w: 100%; h: 1px; transform: scaleX(0); transform-origin: right; animation: lineGrow 3s linear infinite 1s; }
  .cyber-lines span:nth-child(3) { top: 60%; left: 0; w: 100%; h: 1px; transform: scaleX(0); transform-origin: left; animation: lineGrow 3s linear infinite 2s; }
  .cyber-lines span:nth-child(4) { top: 80%; right: 0; w: 100%; h: 1px; transform: scaleX(0); transform-origin: right; animation: lineGrow 3s linear infinite 1.5s; }

  .corner-elements span {
    position: absolute;
    width: 20px;
    height: 20px;
    border: 2px solid rgba(99, 102, 241, 0.4);
    z-index: 40;
    transition: all 0.3s ease;
    pointer-events: none;
  }

  .corner-elements span:nth-child(1) { top: 15px; left: 15px; border-right: 0; border-bottom: 0; }
  .corner-elements span:nth-child(2) { top: 15px; right: 15px; border-left: 0; border-bottom: 0; }
  .corner-elements span:nth-child(3) { bottom: 15px; left: 15px; border-right: 0; border-top: 0; }
  .corner-elements span:nth-child(4) { bottom: 15px; right: 15px; border-left: 0; border-top: 0; }

  #card:hover .corner-elements span {
    border-color: rgba(0, 255, 170, 0.8);
    box-shadow: 0 0 10px rgba(0, 255, 170, 0.3);
  }

  .scan-line {
    position: absolute;
    inset: 0;
    background: linear-gradient(to bottom, transparent, rgba(0, 255, 170, 0.3) 50%, transparent);
    transform: translateY(-100%);
    animation: scanMove 2.5s cubic-bezier(0.4, 0, 0.2, 1) infinite;
    z-index: 50;
    pointer-events: none;
    transition: opacity 0.3s ease;
  }

  @keyframes lineGrow {
    0% { transform: scaleX(0); opacity: 0; }
    50% { transform: scaleX(1); opacity: 1; }
    100% { transform: scaleX(0); opacity: 0; }
  }

  @keyframes scanMove {
    0% { transform: translateY(-100%); }
    100% { transform: translateY(100%); }
  }
`;

export default ImageDetection;
