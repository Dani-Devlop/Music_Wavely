#!/bin/bash
# Generate Wavely prototype album covers
cd /home/z/my-project/public/covers || exit 1

z-ai image -p "Album cover art, retrowave synthwave sunset, neon grid horizon, purple and magenta mountains silhouette, glowing green accent lights, 80s retro aesthetic, no text, no letters, high quality, detailed" -o neon-horizon.png -s 1024x1024 &
P1=$!
z-ai image -p "Album cover art, dark moody close-up of luminous flowers blooming at night, deep green and black tones, cinematic lighting, mysterious atmosphere, no text, no letters, high quality" -o midnight-bloom.png -s 1024x1024 &
P2=$!
z-ai image -p "Album cover art, abstract glowing green circuit board patterns flowing like sound waves on dark background, futuristic electronic music aesthetic, no text, no letters, high quality" -o green-circuit.png -s 1024x1024 &
P3=$!
z-ai image -p "Album cover art, paper airplane flying over misty mountain valley at dawn, warm golden light, nostalgic indie folk aesthetic, minimalist, no text, no letters, high quality" -o paper-planes.png -s 1024x1024 &
P4=$!
wait $P1 $P2 $P3 $P4
echo "=== BATCH 1 DONE ==="

z-ai image -p "Album cover art, cozy rainy window with warm lamp light in a dim room, lofi aesthetic, plants and headphones on wooden table, illustration style, no text, no letters, high quality" -o deep-focus.png -s 1024x1024 &
Q1=$!
z-ai image -p "Album cover art, grunge rock texture with torn red velvet and black smoke, dramatic high contrast, raw energy, no text, no letters, high quality" -o velvet-static.png -s 1024x1024 &
Q2=$!
z-ai image -p "Album cover art, golden hour sky gradient with birds flying over calm ocean, warm orange and amber tones, dreamy pop aesthetic, no text, no letters, high quality" -o golden-hour.png -s 1024x1024 &
Q3=$!
z-ai image -p "Album cover art, intricate Persian geometric tilework pattern with turquoise and gold, traditional islamic art meets modern design, elegant, no text, no letters, high quality" -o persian-echoes.png -s 1024x1024 &
Q4=$!
wait $Q1 $Q2 $Q3 $Q4
echo "=== BATCH 2 DONE ==="
ls -la /home/z/my-project/public/covers/
