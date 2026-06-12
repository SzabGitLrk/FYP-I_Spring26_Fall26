import * as THREE from 'three';
import { FBXLoader } from 'three/addons/loaders/FBXLoader.js';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';

// ─── Scene Setup ─────────────────────────────────────────────────────────────
const container = document.getElementById('avatar-screen');
const scene     = new THREE.Scene();
scene.background = new THREE.Color('#1A1A1E');

const camera = new THREE.PerspectiveCamera(45, container.clientWidth / container.clientHeight, 1, 2000);
camera.position.set(0, 150, 250);

const renderer = new THREE.WebGLRenderer({ antialias: true });
renderer.setSize(container.clientWidth, container.clientHeight);
renderer.shadowMap.enabled = true;
container.appendChild(renderer.domElement);

const controls = new OrbitControls(camera, renderer.domElement);
controls.target.set(0, 100, 0);
controls.update();

scene.add(new THREE.HemisphereLight(0xffffff, 0x444444, 1.5));
const dirLight = new THREE.DirectionalLight(0xffffff, 1.5);
dirLight.position.set(100, 200, 100);
scene.add(dirLight);

// ─── Animation State ──────────────────────────────────────────────────────────
const clock = new THREE.Clock();
const loader = new FBXLoader();
let mixer = null;
let avatar = null;
let currentAction = null;
let avatarReady = false;
let lastPlayedWord = null;
let isAnimating = false;
const LoopOnce = 2200;
// Lower-body bone snap: saved idle quats restored after each sign frame
let lowerBodyIdleQuats = null; // Map<Bone, Quaternion>
// Sequential word-spelling queue
let signQueue = [];
let lastWord = null; // full word for repeat

// Bone index maps
const avatarBoneByStripped = new Map();
const avatarBoneByOriginal = new Map();

// Galtis world-copy state
let animSkeleton = null;  // Hidden Galtis FBX scene object
let animMixer = null;     // Mixer driving the Galtis skeleton
let animBonePairs = null; // Array<{galtis, mixamo, depth}> sorted parent→child

// ─── Normalise bone names ─────────────────────────────────────────────────────
function normalise(name) {
    return name
        .toLowerCase()
        .replace(/^[^|]*\|/, '')
                .replace(/^mixamorig\d*:?/, '')
        .replace(/^galtis[_:]?rig[_:]?/i, '')
        .replace(/^ctrl_/, '').replace(/^ik_/, '').replace(/^fk_/, '')
        .replace(/^galtis[_:]?/i, '')
        .replace(/^[_\d]+/, '')
        .replace(/^bone_?|^joint_?/i, '')
        .replace(/_l$/, 'left').replace(/_r$/, 'right')
        .replace(/^l_/i, 'left').replace(/^r_/i, 'right')
        .replace(/^[a-z]_/i, '')
        .replace(/_0(\d)$/, '$1')
        .replace(/[_\s]+/g, '')
        .toLowerCase();
}

// ─── Galtis → Mixamo bone name map ───────────────────────────────────────────
const GALTIS_TO_MIXAMO = {
    'hiproot': 'hips', 'hip_root': 'hips', 'locator_root': 'hips', 'hips': 'hips',
    'chest1': 'spine', 'chest2': 'spine1', 'chest3': 'spine2', 'chest4': 'spine2',
    'neck': 'neck', 'head': 'head',
    'collarleft': 'leftshoulder', 'bicepleft': 'leftarm',
    'forearmleft': 'leftforearm', 'handleft': 'lefthand',
    'collarright': 'rightshoulder', 'bicepright': 'rightarm',
    'forearmright': 'rightforearm', 'handright': 'righthand',
    'thighleft': 'leftupleg', 'shinleft': 'leftleg', 'footleft': 'leftfoot', 'toeleft': 'lefttoebase',
    'thighright': 'rightupleg', 'shinright': 'rightleg', 'footright': 'rightfoot', 'toeright': 'righttoebase',
    'thumb1left': 'lefthandthumb1', 'thumb2left': 'lefthandthumb2', 'thumb3left': 'lefthandthumb3',
    'index1left': 'lefthandindex1', 'index2left': 'lefthandindex2', 'index3left': 'lefthandindex3',
    'middle1left': 'lefthandmiddle1', 'middle2left': 'lefthandmiddle2', 'middle3left': 'lefthandmiddle3',
    'ring1left': 'lefthandring1', 'ring2left': 'lefthandring2', 'ring3left': 'lefthandring3',
    'pinky1left': 'lefthandpinky1', 'pinky2left': 'lefthandpinky2', 'pinky3left': 'lefthandpinky3',
    'thumb1right': 'righthandthumb1', 'thumb2right': 'righthandthumb2', 'thumb3right': 'righthandthumb3',
    'index1right': 'righthandindex1', 'index2right': 'righthandindex2', 'index3right': 'righthandindex3',
    'middle1right': 'righthandmiddle1', 'middle2right': 'righthandmiddle2', 'middle3right': 'righthandmiddle3',
    'ring1right': 'righthandring1', 'ring2right': 'righthandring2', 'ring3right': 'righthandring3',
    'pinky1right': 'righthandpinky1', 'pinky2right': 'righthandpinky2', 'pinky3right': 'righthandpinky3',
    // Extra bones from "Full" variant files
    'wristleft': 'lefthand', 'wristright': 'righthand',
    'elbowleft': 'leftforearm', 'elbowright': 'rightforearm',
    'kneeleft': 'leftleg', 'kneeright': 'rightleg',
    'palmleft': 'lefthand', 'palmright': 'righthand',
};

// ─── Discard lists ────────────────────────────────────────────────────────────
const DISCARD_BONES = new Set([
    'galtisrig', 'headtarget', 'eyecontroller', 'eyecontrollerleft',
    'eyecontrollerright', 'eyeleft', 'eyeright', 'locator',
    'headtopend', 'toeend', 'betajoints', 'betasurface', 'xbot',
    'armature', 'root', 'galtisriggaltisrig', 'galtis_rig',
    'ik_handle', 'polevector', 'aimtarget', 'upnode',
    'kneeaim', 'footaim', 'handik', 'footik',
    'eyeleft', 'eyeright', 'controllerleft', 'controllerright', 'baseleft', 'baseright',
]);
const DISCARD_PROPERTIES = ['morphtargetinfluences', 'morphtargetdictionary', 'visible', 'material'];

// ─── Animation Name Mapping ───────────────────────────────────────────────────
const ANIMATION_MAP = {
    'a': 'A', 'b': 'B', 'c': 'C', 'd': 'D', 'e': 'E', 'f': 'F', 'g': 'G',
    'h': 'H', 'i': 'I', 'j': 'J', 'k': 'K', 'l': 'L', 'm': 'M', 'n': 'N',
    'o': 'O', 'p': 'P', 'q': 'Q', 'r': 'R', 's': 'S', 't': 'T', 'u': 'U',
    'v': 'V', 'w': 'W', 'x': 'X', 'y': 'Y', 'z': 'Z',
    'drink': 'Drinking', 'drinking': 'Drinking', 'thirsty': 'Drinking',
    'water': 'Drinking', 'cup': 'Drinking',
    'bbq': 'BBQ', 'barbecue': 'BBQ', 'grill': 'BBQ', 'food': 'BBQ',
    'idle': 'Idle', 'rest': 'Idle', 'neutral': 'Idle', 'stop': 'Idle', 'pause': 'Idle',
    'hello': 'H', 'hi': 'H', 'hey': 'H', 'yes': 'Y', 'yeah': 'Y', 'ok': 'O',
    'no': 'N', 'not': 'N', 'go': 'G', 'come': 'C', 'here': 'H',
    'good': 'G', 'great': 'G', 'better': 'B', 'bad': 'B', 'sad': 'S', 'mad': 'M',
    'thanks': 'T', 'thank': 'T', 'thankyou': 'T', 'please': 'P', 'sorry': 'S',
    'help': 'H', 'need': 'N', 'want': 'W', 'sleep': 'S', 'bed': 'B',
    'eat': 'E', 'hungry': 'H', 'love': 'L', 'like': 'L',
    'person': 'P', 'people': 'P', 'man': 'M', 'woman': 'W',
    'time': 'T', 'when': 'W', 'where': 'W', 'what': 'W',
    'look': 'L', 'see': 'S', 'watch': 'W',
    'listen': 'L', 'hear': 'H', 'speak': 'S', 'talk': 'T',
    'wait': 'W', 'stay': 'S', 'find': 'F', 'have': 'H',
    'sick': 'S', 'owie': 'O', 'bath': 'B', 'room': 'R',
    'callonphone': 'C', 'night': 'N', 'yesterday': 'Y', 'brother': 'B',
    'awake': 'A',
};

function getAnimationFileName(word) {
    if (!word) return 'Idle';
    const lw = word.toLowerCase().trim();
    if (ANIMATION_MAP[lw]) return ANIMATION_MAP[lw];
    if (lw.length === 1 && /[a-z]/.test(lw)) return lw.toUpperCase();
    const cw = lw.replace(/[^\w]/g, '');
    if (ANIMATION_MAP[cw]) return ANIMATION_MAP[cw];
    if (cw && /[a-z]/.test(cw[0])) return cw[0].toUpperCase();
    return 'Idle';
}

// ─── Index avatar bones ──────────────────────────────────────────────────────
function indexAvatarBones(avatarObj) {
    avatarBoneByStripped.clear(); avatarBoneByOriginal.clear();
    avatarObj.traverse(node => {
        if (!node.name) return;
        avatarBoneByStripped.set(normalise(node.name), node.name);
        avatarBoneByOriginal.set(node.name.toLowerCase(), node.name);
    });
    console.log(`🦴 Avatar bones indexed: ${avatarBoneByStripped.size}`);
}

// ─── Extract clip from FBX object ────────────────────────────────────────────
function extractClip(animObj) {
    if (animObj.animations && animObj.animations.length > 0) return animObj.animations[0];
    let found = null;
    animObj.traverse(c => { if (!found && c.animations && c.animations.length > 0) found = c.animations[0]; });
    return found;
}

// ─── Get depth of a bone in its skeleton hierarchy ───────────────────────────
function getBoneDepth(bone) {
    let d = 0;
    let p = bone.parent;
    while (p) { d++; p = p.parent; }
    return d;
}

// ─── Log animation track bones ───────────────────────────────────────────────
function logTrackBones(animObj, label) {
    const names = new Set();
    const collect = (o) => {
        if (!o.animations) return;
        for (const clip of o.animations) {
            for (const t of clip.tracks) {
                const dot = t.name.lastIndexOf('.');
                if (dot > 0) names.add(t.name.slice(0, dot));
            }
        }
    };
    collect(animObj); animObj.traverse(c => collect(c));
    if (names.size > 0) {
        const arr = [...names].slice(0, 40);
        console.log(`🎯 ${label} tracks (${names.size}): [${arr.join(', ')}${names.size > 40 ? '...' : ''}]`);
    }
}

// ─── Word Spelling ─────────────────────────────────────────────────────────────
function playWord(word) {
    if (!mixer) { console.warn('playWord: ⏳ Avatar still loading...'); return; }
    if (!word || !word.trim()) return;
    const lw = word.toLowerCase().trim();
    console.log(`playWord: "${word}" → lw="${lw}"`);
    const mapped = ANIMATION_MAP[lw];
    // Use special multi-character animations (e.g. "drink" → "Drinking")
    // but ignore single-letter mappings so multi-letter words get spelled out
    if (mapped && mapped.length > 1) {
        console.log(`playWord: special animation → ${mapped}`);
        playSign(lw);
        return;
    }
    // Otherwise spell it out letter by letter
    const letters = lw.split('').filter(c => /[a-z]/.test(c));
    console.log(`playWord: letters=[${letters.join(',')}] (${letters.length})`);
    if (letters.length === 0) return;
    if (letters.length === 1) { console.log(`playWord: single letter → playSign`); playSign(letters[0]); return; }
    lastWord = word;
    lastPlayedWord = word;
    signQueue = letters.slice(); // copy
    console.log(`playWord: signQueue=[${signQueue.join(',')}] → playNextInQueue`);
    clearTimeout(window._animTimer);
    playNextInQueue();
}
function playNextInQueue() {
    console.log(`playNextInQueue: queue=[${signQueue.join(',')}] (${signQueue.length})`);
    if (signQueue.length === 0) { console.log(`playNextInQueue: queue empty → idle in 300ms`); setTimeout(() => playSign('idle'), 300); return; }
    const next = signQueue.shift();
    console.log(`🔤 Spelling: "${next}" (${signQueue.length} left in queue)`);
    playSign(next);
}

// ─── Play Sign ────────────────────────────────────────────────────────────────
function playSign(word) {
    if (!mixer) { console.warn('⏳ Avatar still loading...'); return; }
    if (!word || !word.trim()) { console.warn('❌ Empty word'); return; }

    const animFileName = getAnimationFileName(word);
    const filePath = `assets/${animFileName}.fbx`;
    console.log(`🎬 "${word}" → ${animFileName}.fbx`);

    loader.load(filePath, (animObj) => {
        try {
            logTrackBones(animObj, animFileName);
            const rawClip = extractClip(animObj);
            if (!rawClip) {
                console.warn(`⚠️ No clip in ${filePath}`);
                if (animFileName !== 'Idle') { playSign('idle'); }
                return;
            }

            // ─── Detect skeleton type ────────────────────────────────────────
            const hasMixamorig = rawClip.tracks.some(t => t.name.toLowerCase().includes('mixamorig'));

            if (hasMixamorig) {
                // ═══ MIXAMO PATH (use clip directly — names already match) ═══
                console.log(`🎯 Mixamo — direct clip (${rawClip.tracks.length} tracks)`);
                const useClip = rawClip;
                if (useClip.tracks.length === 0) {
                    if (animFileName !== 'Idle') { playSign('idle'); }
                    return;
                }
                cleanupGaltis();
                const isIdle = animFileName === 'Idle';
                // Keep ONLY right-side arm/forearm/hand/fingers (shoulder stays in Idle).
                // Left side stays in Idle; neck, head, torso, legs all locked.
                const finalClip = isIdle ? useClip : new THREE.AnimationClip(useClip.name, useClip.duration,
                    useClip.tracks.filter(t => {
                        const dot = t.name.lastIndexOf('.');
                        if (dot < 0) return false;
                        const n = normalise(t.name.slice(0, dot));
                        if (n.includes('armature') || n.includes('locator') || n === 'root') return false;
                        if (n.includes('hip') || n.includes('spine') || n.includes('upleg') ||
                            n.includes('leg') || n.includes('foot') || n.includes('toe')) return false;
                        if (n.includes('neck') || n.includes('head')) return false;
                        if (n.includes('left')) return false;
                        if (!n.includes('right')) return false;
                        if (n.includes('shoulder')) return false;
                        return n.includes('arm') || n.includes('forearm') ||
                               n.includes('hand') || n.includes('thumb') || n.includes('index') ||
                               n.includes('middle') || n.includes('ring') || n.includes('pinky');
                    })
                );

                if (isIdle) {
                    // Clear saved lower-body snapshot (will recapture)
                    lowerBodyIdleQuats = null;
                    // Play full Idle on the single mixer
                    if (mixer) mixer.uncacheRoot(avatar);
                    mixer = new THREE.AnimationMixer(avatar);
                    const action = mixer.clipAction(finalClip);
                    action.reset();
                    action.setLoop(THREE.LoopRepeat, Infinity);
                    action.clampWhenFinished = false;
                    action.play();
                    currentAction = action;
                    console.log(`🎵 Idle loop started`);
                } else {
                    // Play sign: start sign action WITH crossfade from current (Idle)
                    // after fade, keep Idle at trace weight so lower-body bones stay driven
                    const prevAction = currentAction;
                    const signAction = mixer.clipAction(finalClip);
                    signAction.reset();
                    signAction.setLoop(LoopOnce, 1);
                    signAction.clampWhenFinished = true;
                    if (prevAction) {
                        // Crossfade: prev fades out, sign fades in
                        signAction.crossFadeFrom(prevAction, 0.25, false);
                    } else {
                        signAction.fadeIn(0.15);
                    }
                    signAction.play();
                    currentAction = signAction;

                    // Snapshot all bones EXCEPT the right-side signing chain
                    // (right arm/forearm/hand/fingers). Shoulder stays locked too.
                    if (!lowerBodyIdleQuats) {
                        lowerBodyIdleQuats = new Map();
                        avatar.traverse(node => {
                            if (!node.isBone) return;
                            const n = normalise(node.name);
                            // Skip right-side arm/forearm/hand/fingers (free to animate)
                            if (n.includes('right') && (
                                n.includes('arm') || n.includes('forearm') ||
                                n.includes('hand') || n.includes('thumb') || n.includes('index') ||
                                n.includes('middle') || n.includes('ring') || n.includes('pinky')
                            )) return;
                            lowerBodyIdleQuats.set(node, node.quaternion.clone());
                        });
                        console.log(`📸 Captured ${lowerBodyIdleQuats.size} idle bone quats (right shoulder locked)`);
                    }

                    lastPlayedWord = word;
                    isAnimating = true;
                    const ms = Math.max((finalClip.duration * 1000) + 500, 1000);
                    clearTimeout(window._animTimer);
                    window._animTimer = setTimeout(() => {
                        isAnimating = false;
                        console.log(`⏰ Timeout: sign="${word}" queue=[${signQueue.join(',')}] (${signQueue.length})`);
                        if (signQueue.length > 0) { console.log(`⏰ → playNextInQueue`); playNextInQueue(); return; }
                        console.log(`⏰ → queue empty`);
                        if (!lastPlayedWord || lastPlayedWord === 'idle') return;
                        playSign('idle');
                    }, ms);
                    console.log(`✅ Playing "${word}" — ${useClip.tracks.length} tracks (snap lower body)`);
                }

            } else {
                // ═══ GALTIS PATH (world rotation copy) ═══════════════════════
                console.log(`🎯 Galtis — world rotation copy`);
                // Remove previous Galtis skeleton
                cleanupGaltis();

                // Collect unique bone names from animation tracks
                const trackBoneNames = [...new Set(rawClip.tracks.map(t => {
                    const dot = t.name.lastIndexOf('.');
                    return dot > 0 ? t.name.slice(0, dot) : null;
                }).filter(Boolean))];
                console.log(`⚡ ${trackBoneNames.length} track bone names`);

                // Find each tracked bone in the Galtis hierarchy (accept any Object3D)
                const galtisBones = [];
                for (const bname of trackBoneNames) {
                    let bone = null;
                    animObj.traverse(c => {
                        if (bone || !c.name) return;
                        if (c.name === bname || c.name.toLowerCase() === bname.toLowerCase()) bone = c;
                    });
                    // Namespace fallback (last segment after ':')
                    if (!bone) {
                        const seg = bname.includes(':') ? bname.split(':').pop() : bname;
                        const lseg = seg.toLowerCase();
                        animObj.traverse(c => {
                            if (bone || !c.name) return;
                            if (c.name.toLowerCase() === lseg) bone = c;
                        });
                    }
                    if (bone) {
                        galtisBones.push({ name: bname, bone });
                    } else {
                        console.log(`  ❌ Not found in hierarchy: ${bname}`);
                    }
                }
                console.log(`⚡ Found ${galtisBones.length} / ${trackBoneNames.length} bones in Galtis hierarchy`);

                if (galtisBones.length < 5) {
                    console.warn(`⚠️ Too few Galtis bones found — fallback Idle`);
                    if (animFileName !== 'Idle') { playSign('idle'); }
                    return;
                }

                // Build bone pairs: map each Galtis bone to the corresponding Mixamo avatar bone
                const bonePairs = [];
                const failed = [];
                for (const { name, bone: gBone } of galtisBones) {
                    const normed = normalise(name);
                    const mixamoNorm = GALTIS_TO_MIXAMO[normed];
                    if (!mixamoNorm) { failed.push(`${name}→${normed}→?`); continue; }
                    const origName = avatarBoneByStripped.get(mixamoNorm);
                    if (!origName) { failed.push(`${name}→${mixamoNorm}→?`); continue; }
                    const mBone = avatar.getObjectByName(origName);
                    if (!mBone) { failed.push(`${name}→${origName}→missing`); continue; }
                    bonePairs.push({
                        galtis: gBone,
                        mixamo: mBone,
                        depth: getBoneDepth(gBone)
                    });
                }
                console.log(`⚡ Mapped ${bonePairs.length} bone pairs`);
                if (failed.length > 0) console.log(`⚡ Failed: [${failed.join(', ')}]`);

                if (bonePairs.length < 5) {
                    console.warn(`⚠️ Too few mapped pairs — fallback Idle`);
                    if (animFileName !== 'Idle') { playSign('idle'); }
                    return;
                }

                // Sort by hierarchy depth (parents before children) so world matrices update correctly
                bonePairs.sort((a, b) => a.depth - b.depth);

                // Hide Galtis meshes
                animObj.traverse(c => { if (c.isMesh || c.isSkinnedMesh) c.visible = false; });

                // Position at avatar's origin
                animObj.position.set(0, 0, 0);
                animObj.quaternion.identity();
                scene.add(animObj);

                // Save state
                animSkeleton = animObj;
                animBonePairs = bonePairs;
                animMixer = new THREE.AnimationMixer(animObj);

                // Play raw clip on Galtis skeleton
                const rawAction = animMixer.clipAction(rawClip);
                rawAction.reset();
                rawAction.setLoop(LoopOnce, 1);
                rawAction.clampWhenFinished = true;
                rawAction.fadeIn(0.15);
                rawAction.play();

                // Stop avatar mixer (Galtis drives via world copy)
                if (mixer) mixer.stopAllAction();
                currentAction = null;

                lastPlayedWord = word;
                isAnimating = true;
                const ms = (rawClip.duration * 1000) + 300;
                clearTimeout(window._animTimer);
                window._animTimer = setTimeout(() => { isAnimating = false; cleanupGaltis(); }, ms);
                console.log(`✅ Playing "${word}" — ${bonePairs.length} pairs (world-copy, ${rawClip.duration.toFixed(2)}s)`);
            }
        } catch (err) {
            console.error(`❌ Animation error: ${err.message}`);
        }
    }, undefined, (err) => {
        console.error(`❌ File not found: ${filePath}`);
        if (animFileName !== 'Idle') { playSign('idle'); }
    });
}

// ─── Cleanup Galtis skeleton ──────────────────────────────────────────────────
function cleanupGaltis() {
    if (animMixer) { animMixer.stopAllAction(); animMixer = null; }
    if (animSkeleton) { scene.remove(animSkeleton); animSkeleton = null; }
    animBonePairs = null;
}

// ─── World rotation copy (called each frame) ──────────────────────────────────
function applyWorldCopy() {
    if (!animBonePairs || !avatar) return;
    const worldQ = new THREE.Quaternion();
    const parentWorldQ = new THREE.Quaternion();
    const worldPos = new THREE.Vector3();
    const parentWorldPos = new THREE.Vector3();

    for (const pair of animBonePairs) {
        const g = pair.galtis;
        const m = pair.mixamo;
        if (!g || !m) continue;

        // Copy world rotation: localQ = inv(parentWorldQ) * childWorldQ
        g.getWorldQuaternion(worldQ);
        const parent = m.parent;
        if (parent) {
            parent.getWorldQuaternion(parentWorldQ);
            m.quaternion.copy(parentWorldQ.invert().multiply(worldQ));
        } else {
            m.quaternion.copy(worldQ);
        }
        m.updateMatrix();
    }

    // Copy root bone's world position for body movement
    if (animBonePairs.length > 0) {
        const first = animBonePairs[0];
        const gRoot = first.galtis;
        const mRoot = first.mixamo;
        const normed = normalise(gRoot.name);
        if (normed === 'hips' || normed === 'hiproot' || normed === 'hip_root' || normed === 'locator_root') {
            gRoot.getWorldPosition(worldPos);
            const parent = mRoot.parent;
            if (parent) {
                parent.getWorldPosition(parentWorldPos);
                mRoot.position.set(
                    worldPos.x - parentWorldPos.x,
                    worldPos.y - parentWorldPos.y,
                    worldPos.z - parentWorldPos.z
                );
            } else {
                mRoot.position.copy(worldPos);
            }
            mRoot.updateMatrix();
        }
    }
}

// ─── Retarget animation clip to avatar skeleton (for Mixamo animations) ──────
function retargetClip(clip) {
    const retargetedTracks = [];
    let skipped = 0;
    let matched = 0;

    for (const track of clip.tracks) {
        try {
            const dotIdx = track.name.lastIndexOf('.');
            if (dotIdx === -1) { skipped++; continue; }
            const property = track.name.slice(dotIdx);
            const rawBone = track.name.slice(0, dotIdx);
            const normKey = normalise(rawBone);

            const propLower = property.toLowerCase().replace('.', '');
            if (DISCARD_PROPERTIES.some(p => propLower.includes(p))) { skipped++; continue; }
            if (DISCARD_BONES.has(normKey)) { skipped++; continue; }

            let resolvedName = avatarBoneByStripped.get(normKey);

            if (!resolvedName) {
                const remapped = GALTIS_TO_MIXAMO[normKey];
                if (remapped) resolvedName = avatarBoneByStripped.get(remapped);
            }

            if (!resolvedName) {
                // Try substring: avatar bone contains animation bone name
                for (const [an, ao] of avatarBoneByStripped) {
                    if (normKey.length >= 4 && an.includes(normKey) && an.length >= normKey.length + 2) {
                        resolvedName = ao; break;
                    }
                }
            }

            if (!resolvedName && normKey.length >= 5) {
                // Try keyword matching
                const keywords = [...new Set(normKey.match(/thumb|index|middle|ring|pinky|shoulder|arm|forearm|spine|chest|neck|head|hip|leg|thigh|shin|calf|foot|toe|collar|clavicle|elbow|knee|wrist|ankle|hand|finger|left|right/g) || [])];
                if (keywords.length > 0) {
                    let best = null, bestScore = 0;
                    for (const [an, ao] of avatarBoneByStripped) {
                        let score = keywords.filter(k => an.includes(k)).length;
                        if (score > bestScore) { bestScore = score; best = ao; }
                    }
                    if (best && bestScore >= 2) resolvedName = best;
                }
            }

            if (!resolvedName) { skipped++; continue; }

            const newTrack = track.clone();
            newTrack.name = resolvedName + property;
            retargetedTracks.push(newTrack);
            matched++;
        } catch (e) {
            console.warn(`⚠️ Track error: ${track.name} — ${e.message}`);
            skipped++;
        }
    }

    // Mirror 3rd finger joints → 4th joints (quaternion only) so the 4th joint
    // doesn't stay in default pose while 3rd joint curls
    const extraTracks = [];
    for (const track of retargetedTracks) {
        const dotIdx = track.name.lastIndexOf('.');
        if (dotIdx === -1) continue;
        const property = track.name.slice(dotIdx);
        if (property !== '.quaternion' && property !== '.rotation') continue;
        const bone = track.name.slice(0, dotIdx);
        const normKey = normalise(bone);
        const m = normKey.match(/^(lefthand|righthand)(index|middle|ring|pinky|thumb)3$/);
        if (m) {
            const fourthKey = m[1] + m[2] + '4';
            const fourthResolved = avatarBoneByStripped.get(fourthKey);
            if (fourthResolved) {
                const clone = track.clone();
                clone.name = fourthResolved + property;
                extraTracks.push(clone);
            }
        }
    }
    if (extraTracks.length > 0) {
        retargetedTracks.push(...extraTracks);
        matched += extraTracks.length;
        console.log(`➕ Mirrored ${extraTracks.length} 4th-joint tracks`);
    }

    console.log(`⏭️ Retarget: ${matched} matched, ${skipped} skipped`);
    return new THREE.AnimationClip(clip.name, clip.duration, retargetedTracks);
}

// ─── Load Avatar ──────────────────────────────────────────────────────────────
loader.load('assets/BridgeSign_Avatar.fbx', (object) => {
    try {
        avatar = object;
        avatar.scale.set(1, 1, 1);
        avatar.position.set(0, 0, 0);
        scene.add(avatar);
        mixer = new THREE.AnimationMixer(avatar);
        indexAvatarBones(avatar);
        avatarReady = true;
        console.log(`✅ Avatar loaded — ${avatarBoneByStripped.size} bones`);
        const sample = [...avatarBoneByStripped.keys()].slice(0, 30);
        console.log(`🧍 Stripped keys: [${sample.join(', ')}${avatarBoneByStripped.size > 30 ? '...' : ''}]`);
        if (window.uiManager) window.uiManager.updateStatus('ready', 'Avatar ready - Type to animate');
        // Start looping Idle for natural rest pose
        setTimeout(() => playSign('idle'), 100);
    } catch (err) {
        console.error('❌ Avatar setup error:', err);
        avatarReady = false;
    }
}, (p) => {
    const pct = (p.loaded / p.total) * 100;
    console.log(`📊 Avatar: ${pct.toFixed(0)}%`);
}, (err) => {
    console.error('❌ Avatar load error:', err);
    avatarReady = false;
});

// ─── Repeat Last Sign ─────────────────────────────────────────────────────────
function repeatLastSign() {
    if (!lastPlayedWord) { console.warn('⚠️ No previous sign'); return; }
    if (isAnimating) { console.warn('⏳ Still animating'); return; }
    if (lastWord) { playWord(lastWord); return; }
    playSign(lastPlayedWord);
}

window.playSign = playSign;
window.playWord = playWord;
window.repeatLastSign = repeatLastSign;
window.lastPlayedWordFn = () => lastPlayedWord;

// ─── Render Loop ──────────────────────────────────────────────────────────────
function animate() {
    requestAnimationFrame(animate);
    const delta = clock.getDelta();
    if (animMixer) {
        animMixer.update(delta);
        applyWorldCopy();
    } else if (mixer) {
        mixer.update(delta);
        // Restore all non-hand bones to Idle pose after every frame.
        // This locks the entire body except hands/fingers, preventing
        // all rigging/skinning distortion from sign animation tracks.
        if (lowerBodyIdleQuats) {
            for (const [bone, quat] of lowerBodyIdleQuats) {
                bone.quaternion.copy(quat);
            }
        }
    }
    controls.update();
    renderer.render(scene, camera);
}
animate();

// ─── Resize ───────────────────────────────────────────────────────────────────
window.addEventListener('resize', () => {
    const w = container.clientWidth, h = container.clientHeight;
    camera.aspect = w / h; camera.updateProjectionMatrix();
    renderer.setSize(w, h);
});
