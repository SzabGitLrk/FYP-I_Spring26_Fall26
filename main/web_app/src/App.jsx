import React, { useState, useRef } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { Canvas } from '@react-three/fiber';
import { OrbitControls, Environment } from '@react-three/drei';
import { Upload, ShieldCheck, ShieldAlert, Zap, Loader2, Video, Image as ImageIcon } from 'lucide-react';
import axios from 'axios';
import Hero3DImage from './Hero3DImage';
import HeroSection from './HeroSection';

function ScannerApp() {
  const [file, setFile] = useState(null);
  const [preview, setPreview] = useState('');
  const [type, setType] = useState('image');
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState(null);
  const fileInputRef = useRef(null);

  const handleFileChange = (e) => {
    const selected = e.target.files[0];
    if (selected) {
      setFile(selected);
      setPreview(URL.createObjectURL(selected));
      setResult(null);
    }
  };

  const handleScan = async () => {
    if (!file) return;
    setLoading(true);
    const formData = new FormData();
    formData.append('file', file);
    try {
      const endpoint = type === 'image' ? '/predict/image' : '/predict/video';
      const res = await axios.post(`http://localhost:8000${endpoint}`, formData, {
        headers: { 'Content-Type': 'multipart/form-data' },
      });
      setTimeout(() => { setResult(res.data); setLoading(false); }, 1500);
    } catch {
      setLoading(false);
      alert('Error connecting to the backend scanner. Make sure app.py is running.');
    }
  };

  const reset = () => { setFile(null); setPreview(''); setResult(null); };

  return (
    <div className="min-h-screen flex flex-col relative overflow-hidden bg-[#05050a]">
      {/* Grid bg */}
      <div className="fixed inset-0 z-0" style={{
        backgroundSize: '50px 50px',
        backgroundImage: 'linear-gradient(to right,rgba(0,240,255,.03) 1px,transparent 1px),linear-gradient(to bottom,rgba(0,240,255,.03) 1px,transparent 1px)',
      }}/>

      {/* Navbar */}
      <nav className="relative z-50 m-4 p-6 flex justify-between items-center rounded-2xl border border-[rgba(0,240,255,0.2)] bg-[rgba(10,15,30,0.6)] backdrop-blur-xl shadow-[0_4px_30px_rgba(0,0,0,0.5)]">
        <div className="flex items-center gap-3">
          <Zap className="text-[#00f0ff] w-8 h-8" />
          <h1 className="text-2xl font-bold tracking-widest text-white uppercase" style={{textShadow:'0 0 10px rgba(0,240,255,0.5)'}}>
            DeepGuard<span className="text-[#00f0ff]">.AI</span>
          </h1>
        </div>
        <div className="flex gap-4">
          {['image','video'].map(t => (
            <button key={t} onClick={() => { setType(t); reset(); }}
              className={`px-4 py-2 rounded-md font-semibold transition-all uppercase text-sm ${type===t ? 'bg-[#00f0ff] text-black shadow-[0_0_15px_#00f0ff]' : 'text-gray-400 hover:text-white'}`}>
              {t} scan
            </button>
          ))}
        </div>
      </nav>

      {/* Main */}
      <main className="relative z-10 flex-1 flex flex-col lg:flex-row items-center justify-center p-8 gap-12">
        {/* 3D Hero */}
        <motion.div initial={{opacity:0,x:-50}} animate={{opacity:1,x:0}} transition={{duration:0.8}}
          className="w-full lg:w-1/2 h-[500px] hidden lg:flex items-center justify-center relative">
          <div className="absolute inset-0 bg-[#00f0ff] opacity-10 blur-[100px] rounded-full"/>
          <Canvas camera={{ position:[0,0,5], fov:50 }}>
            <ambientLight intensity={0.5}/>
            <directionalLight position={[10,10,5]} intensity={1}/>
            <Environment preset="city"/>
            <Hero3DImage/>
            <OrbitControls enableZoom={false} enablePan={false}/>
          </Canvas>
        </motion.div>

        {/* Scanner card */}
        <motion.div initial={{opacity:0,y:50}} animate={{opacity:1,y:0}} transition={{duration:0.8,delay:0.2}}
          className="w-full lg:w-1/2 max-w-md">
          <div className="relative p-8 flex flex-col gap-6 overflow-hidden rounded-2xl border border-[rgba(0,240,255,0.2)] bg-[rgba(10,15,30,0.6)] backdrop-blur-xl shadow-[0_4px_30px_rgba(0,0,0,0.5),inset_0_0_20px_rgba(0,240,255,0.05)] hover:shadow-[0_0_15px_rgba(0,240,255,0.5)] hover:border-[#00f0ff] transition-all">
            <h2 className="text-3xl font-bold text-center uppercase mb-2" style={{textShadow:'0 0 10px rgba(0,240,255,0.5)',color:'#e0f2fe'}}>
              Neural {type} Analysis
            </h2>

            {!file ? (
              <div onClick={() => fileInputRef.current.click()}
                className="border-2 border-dashed border-[rgba(0,240,255,0.3)] rounded-xl p-10 flex flex-col items-center justify-center gap-4 cursor-pointer hover:border-[#00f0ff] hover:bg-[rgba(0,240,255,0.05)] transition-all group">
                <div className="w-16 h-16 rounded-full bg-[rgba(0,240,255,0.1)] flex items-center justify-center group-hover:scale-110 transition-transform">
                  {type==='image' ? <ImageIcon className="w-8 h-8 text-[#00f0ff]"/> : <Video className="w-8 h-8 text-[#00f0ff]"/>}
                </div>
                <p className="text-center text-gray-300 font-medium">
                  Drop your {type} here or <span className="text-[#00f0ff]">browse</span>
                </p>
                <p className="text-xs text-gray-500">Supports JPG, PNG, MP4, AVI</p>
              </div>
            ) : (
              <div className="relative rounded-xl overflow-hidden bg-black/50 border border-white/10 flex items-center justify-center min-h-[300px]">
                {type==='image'
                  ? <img src={preview} alt="Preview" className="max-w-full max-h-[300px] object-contain"/>
                  : <video src={preview} controls className="max-w-full max-h-[300px] object-contain"/>
                }
                {loading && (
                  <div className="absolute inset-0 overflow-hidden">
                    <div className="absolute top-0 left-0 w-full h-1 bg-[#00f0ff] z-10"
                      style={{boxShadow:'0 0 20px #00f0ff, 0 0 40px #00f0ff', animation:'scan 2s linear infinite'}}/>
                    <div className="absolute inset-0 pointer-events-none"
                      style={{background:'linear-gradient(to bottom,rgba(0,240,255,0.2) 0%,transparent 100%)',animation:'scan-gradient 2s linear infinite'}}/>
                    <style>{`
                      @keyframes scan{0%{top:0}50%{top:100%}100%{top:0}}
                      @keyframes scan-gradient{0%{transform:translateY(-100%)}50%{transform:translateY(0)}100%{transform:translateY(-100%)}}
                    `}</style>
                  </div>
                )}
              </div>
            )}

            <input type="file" accept={type==='image'?'image/*':'video/*'} className="hidden" ref={fileInputRef} onChange={handleFileChange}/>

            <div className="flex gap-4">
              {file && !result && !loading && (
                <button onClick={handleScan}
                  className="flex-1 bg-gradient-to-r from-[#00f0ff] to-[#0080ff] text-black font-bold py-3 px-6 rounded-lg uppercase tracking-wide hover:shadow-[0_0_20px_#00f0ff] transition-all flex justify-center items-center gap-2">
                  <Zap size={20}/> Initialize Scan
                </button>
              )}
              {loading && (
                <button disabled className="flex-1 bg-gray-800 text-[#00f0ff] font-bold py-3 px-6 rounded-lg uppercase tracking-wide flex justify-center items-center gap-2 border border-[rgba(0,240,255,0.3)]">
                  <Loader2 size={20} className="animate-spin"/> Analyzing Patterns...
                </button>
              )}
              {file && <button onClick={reset} disabled={loading} className="px-6 py-3 border border-white/20 rounded-lg hover:bg-white/10 transition-all font-semibold disabled:opacity-50 text-white">Reset</button>}
            </div>

            <AnimatePresence>
              {result && (
                <motion.div initial={{opacity:0,height:0}} animate={{opacity:1,height:'auto'}}
                  className={`mt-4 p-5 rounded-lg border flex items-center gap-4 ${result.prediction==='Real'?'bg-green-500/10 border-green-500/50':'bg-red-500/10 border-red-500/50'}`}>
                  <div className={`p-3 rounded-full ${result.prediction==='Real'?'bg-green-500/20 text-green-400':'bg-red-500/20 text-red-400'}`}>
                    {result.prediction==='Real' ? <ShieldCheck size={28}/> : <ShieldAlert size={28}/>}
                  </div>
                  <div>
                    <h3 className={`text-xl font-bold uppercase ${result.prediction==='Real'?'text-green-400':'text-red-400'}`}>
                      {result.prediction} Media Detected
                    </h3>
                    <p className="text-gray-300">Confidence: <span className="font-bold text-white">{result.confidence}</span></p>
                  </div>
                </motion.div>
              )}
            </AnimatePresence>
          </div>
        </motion.div>
      </main>
    </div>
  );
}

import ImageDetection from './ImageDetection';
import VideoDetection from './VideoDetection';
import About from './About';

export default function App() {
  const [view, setView] = React.useState('DASHBAORD');

  if (view === 'IMAGE DETECTION') return <ImageDetection onNavigate={setView} />;
  if (view === 'VIDEO DETECTION') return <VideoDetection onNavigate={setView} />;
  if (view === 'ABOUT') return <About onNavigate={setView} />;
  if (view === 'scanner') return <ScannerApp />; // Legacy scanner view

  return (
    <div>
      <HeroSection onNavigate={setView} />
      {/* CTA to enter scanner */}
      <div className="fixed bottom-6 right-6 z-[200]">
        <button
          onClick={() => setView('IMAGE DETECTION')}
          className="bg-indigo-500 text-white font-bold px-6 py-3 rounded-full shadow-[0_0_20px_rgba(99,102,241,0.5)] hover:scale-105 transition-all text-sm uppercase tracking-wide border border-indigo-400"
        >
          🛡 Image Scanner
        </button>
      </div>
    </div>
  );
}
