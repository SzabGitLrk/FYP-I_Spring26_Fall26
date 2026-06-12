# Quick Troubleshooting Guide

## Avatar Animation Issues

### Issue: Avatar doesn't move when I type a word

**Possible Causes & Solutions:**

1. **Animation file doesn't exist**
   - Check browser console (F12) for this message: `❌ Failed to load animation file: assets/...fbx`
   - Solution: Verify the file exists in `WebApp/assets/` folder
   - Available files: A-Z.fbx, Drinking.fbx, BBQ.fbx, Idle.fbx, BridgeSign_Avatar.fbx

2. **Avatar not loaded yet**
   - Look for: `❌ Mixer not ready - Avatar still loading`
   - Solution: Wait a few seconds for the avatar to load
   - Check network tab to see if BridgeSign_Avatar.fbx is downloaded

3. **Browser console shows no messages**
   - Open Developer Tools (F12 → Console tab)
   - Try typing again and watch for error messages
   - Check if THREE.js library is loaded properly

### Issue: Avatar gets into wrong shape/pose

**Possible Causes & Solutions:**

1. **Wrong animation file is playing**
   - Look in console for: `📝 Attempting to load: "..." → "..." (...fbx)`
   - Verify the mapped name is correct
   - Example: "drink" should map to "Drinking.fbx"

2. **Bone retargeting issues**
   - Check console for: `⏭️ Skipping root position track: ...`
   - These messages are expected - they prevent unwanted movement
   - If no tracks are retargeted: `⚠️ 0 tracks retargeted for...`

3. **Avatar rigging problem**
   - This would require re-exporting the FBX with correct bone names
   - Verify BridgeSign_Avatar.fbx has standard bone names

### Issue: Typing multiple words plays wrong sequence

**Solutions:**

1. **Use spaces between words**
   - Input: `drink water` 
   - Expected: Plays Drinking.fbx → then W.fbx
   - Timing: 1.8 seconds between animations

2. **Words must be in ANIMATION_MAP**
   - Check WebApp/app.js line ~145 for ANIMATION_MAP
   - If word is missing, it uses first letter
   - Example: "unknown" → plays U.fbx

3. **API translation issues**
   - If backend API fails, frontend falls back to letter-by-letter
   - Check console for: `🔄 Using fallback...` message

## Console Debug Messages Explained

### Success Indicators ✅
```
✅ Avatar loaded successfully — 47 bones indexed
📝 Attempting to load: "drink" → "Drinking" (assets/Drinking.fbx)
✅ Playing "drink" (34 tracks, 2.45s)
✅ Playing "a" (12 tracks, 1.20s)
```

### Warning Indicators ⚠️
```
⚠️ No animation clip found in assets/Unknown.fbx
⚠️ 0 tracks retargeted for "word"
⏭️ Skipping root position track: Galtis_Rig.position
```

### Error Indicators ❌
```
❌ Mixer not ready - Avatar still loading
❌ Invalid word provided to playSign
❌ Failed to load animation file: assets/Unknown.fbx
❌ Error processing animation: ...
```

## How to Debug

### Step 1: Open Developer Console
- Press `F12` on keyboard
- Go to "Console" tab
- Keep this open while testing

### Step 2: Type a test word
- Type "hello" and press Enter
- Watch the console for messages

### Step 3: Check the logs
- If you see `❌ Failed to load animation file`
  - The mapping is wrong or file missing
  - Solution: Check ANIMATION_MAP in app.js
  
- If you see `✅ Playing` but no movement
  - Animation loaded but bones don't match
  - Solution: Check avatar rigging

- If you see `❌ Mixer not ready`
  - Avatar still loading
  - Solution: Wait and try again

### Step 4: Test individual letters
- Type: `a`, `b`, `c`
- These should work as A.fbx, B.fbx, C.fbx exist
- If these don't work, it's a fundamental loading issue

## Common Word Mappings

### Directly Available
- `drink` → Drinking.fbx (also: drinking, thirsty, water)
- `bbq` → BBQ.fbx (also: barbecue, grill)
- `idle` → Idle.fbx (also: rest, neutral, pause)
- `a-z` → A.fbx-Z.fbx (single letters)

### Mapped via First Letter
- `hello` → H.fbx
- `yes` → Y.fbx
- `no` → N.fbx
- `good` → G.fbx

## Getting More Animation Files

To support more words with dedicated animations:

1. **Create animation FBX files** in Blender or similar
2. **Name them properly**: MyWord.fbx (CamelCase recommended)
3. **Place in WebApp/assets/** folder
4. **Add to ANIMATION_MAP** in WebApp/app.js:
   ```javascript
   'myword': 'MyWord',
   'my word': 'MyWord',  // Alternative spelling
   ```
5. **Add to backend** in backend/routes/translation_routes.py with same mapping

## Performance Tips

1. **Smooth animations**: Check FPS counter (should be 60)
2. **Reduce visual effects**: Disable shadows if stuttering
3. **Clear browser cache**: Ctrl+Shift+Delete (animations might be cached)
4. **Check system resources**: Open Task Manager (Ctrl+Shift+Esc)

## Still Having Issues?

1. **Check logs**: `logs/dual_sense_ai.log` in project root
2. **Verify setup**: Run health check at `http://localhost:5001/api/health`
3. **Check model status**: `http://localhost:5001/api/status/models`
4. **Review configuration**: Check `backend/config.py`

## Emergency: Reset Everything

If nothing works:

1. **Clear browser cache**: Ctrl+Shift+Delete
2. **Restart backend**: Stop and restart Flask server
3. **Hard refresh browser**: Ctrl+F5 or Cmd+Shift+R
4. **Check all files exist**: 
   - WebApp/assets/BridgeSign_Avatar.fbx
   - WebApp/assets/A.fbx through Z.fbx
   - WebApp/assets/Drinking.fbx
   - WebApp/assets/BBQ.fbx
   - WebApp/assets/Idle.fbx
