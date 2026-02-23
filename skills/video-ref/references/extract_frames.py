#!/usr/bin/env python3
"""
extract_frames.py - Video frame extraction orchestrator for Claude Code.

Uses FFmpeg for all video processing. Standard library only (OpenCV optional for similarity mode).

Modes:
  scene      - FFmpeg scene detection filter (default, no extra deps)
  similarity - OpenCV histogram comparison (requires: pip3 install opencv-python)
  time       - Fixed interval extraction (no extra deps)
"""

import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile


def get_video_info(input_path):
    """Run ffprobe to get video metadata."""
    cmd = [
        "ffprobe", "-v", "quiet",
        "-print_format", "json",
        "-show_format", "-show_streams",
        input_path
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"ffprobe failed: {result.stderr}")

    probe = json.loads(result.stdout)
    video_stream = next(
        (s for s in probe.get("streams", []) if s["codec_type"] == "video"),
        None
    )
    if not video_stream:
        raise RuntimeError("No video stream found in file")

    duration = float(probe["format"].get("duration", 0))
    width = int(video_stream["width"])
    height = int(video_stream["height"])
    fps_parts = video_stream.get("r_frame_rate", "30/1").split("/")
    fps = float(fps_parts[0]) / float(fps_parts[1]) if len(fps_parts) == 2 else 30.0
    total_frames = int(duration * fps)
    file_size = os.path.getsize(input_path)

    return {
        "path": os.path.abspath(input_path),
        "duration_seconds": round(duration, 2),
        "resolution": f"{width}x{height}",
        "width": width,
        "height": height,
        "fps": round(fps, 2),
        "total_frames": total_frames,
        "file_size_mb": round(file_size / (1024 * 1024), 2)
    }


def estimate_scene_frames(input_path, threshold):
    """Count scene-change frames without writing files."""
    cmd = [
        "ffmpeg", "-i", input_path,
        "-vf", f"select='gt(scene,{threshold})',showinfo",
        "-f", "null", "-"
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    count = len(re.findall(r"pts_time:", result.stderr))
    return count + 1  # +1 for the first frame (eq(n,0))


def extract_scene_frames(input_path, output_dir, threshold, scale, quality):
    """Extract frames using FFmpeg scene detection."""
    os.makedirs(output_dir, exist_ok=True)

    vf = f"select='gt(scene\\,{threshold})+eq(n\\,0)',scale=iw*{scale}:-1"
    cmd = [
        "ffmpeg", "-i", input_path,
        "-vf", vf,
        "-qscale:v", str(quality),
        "-vsync", "vfr",
        os.path.join(output_dir, "frame_%04d.jpg")
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"FFmpeg scene extraction failed: {result.stderr[-500:]}")

    return collect_frame_info(output_dir)


def extract_similarity_frames(input_path, output_dir, threshold, scale, quality):
    """Extract frames using OpenCV histogram similarity comparison."""
    try:
        import cv2
        import numpy as np
    except ImportError:
        raise RuntimeError(
            "OpenCV is required for similarity mode. Install with:\n"
            "  pip3 install opencv-python\n"
            "Or use --mode scene (no extra dependencies required)."
        )

    os.makedirs(output_dir, exist_ok=True)
    tmp_all = tempfile.mkdtemp(prefix="video-all-frames-")

    try:
        # Step 1: Extract all frames (scaled + compressed)
        vf = f"scale=iw*{scale}:-1"
        cmd = [
            "ffmpeg", "-i", input_path,
            "-vf", vf,
            "-qscale:v", str(quality),
            os.path.join(tmp_all, "frame_%06d.jpg")
        ]
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            raise RuntimeError(f"FFmpeg extraction failed: {result.stderr[-500:]}")

        all_frames = sorted(glob.glob(os.path.join(tmp_all, "frame_*.jpg")))
        if not all_frames:
            raise RuntimeError("No frames extracted")

        # Step 2: Compare adjacent frames using histogram correlation
        prev_hist = None
        keyframe_index = 0

        for frame_path in all_frames:
            img = cv2.imread(frame_path)
            if img is None:
                continue

            # Calculate HSV histogram
            hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
            hist = cv2.calcHist([hsv], [0, 1], None, [50, 60], [0, 180, 0, 256])
            cv2.normalize(hist, hist)

            if prev_hist is None:
                # Always keep the first frame
                keyframe_index += 1
                dst = os.path.join(output_dir, f"frame_{keyframe_index:04d}.jpg")
                shutil.copy2(frame_path, dst)
                prev_hist = hist
                continue

            # Compare with previous keyframe
            similarity = cv2.compareHist(prev_hist, hist, cv2.HISTCMP_CORREL)

            if similarity < threshold:
                # Significant change detected - keep this frame
                keyframe_index += 1
                dst = os.path.join(output_dir, f"frame_{keyframe_index:04d}.jpg")
                shutil.copy2(frame_path, dst)
                prev_hist = hist
    finally:
        shutil.rmtree(tmp_all, ignore_errors=True)

    return collect_frame_info(output_dir)


def extract_time_frames(input_path, output_dir, interval, scale, quality):
    """Extract frames at fixed time intervals."""
    os.makedirs(output_dir, exist_ok=True)

    fps_value = 1.0 / interval
    vf = f"fps={fps_value},scale=iw*{scale}:-1"
    cmd = [
        "ffmpeg", "-i", input_path,
        "-vf", vf,
        "-qscale:v", str(quality),
        os.path.join(output_dir, "frame_%04d.jpg")
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"FFmpeg time extraction failed: {result.stderr[-500:]}")

    return collect_frame_info(output_dir)


def collect_frame_info(output_dir):
    """Collect info about extracted frame files."""
    frames = []
    for path in sorted(glob.glob(os.path.join(output_dir, "frame_*.jpg"))):
        size = os.path.getsize(path)
        frames.append({
            "filename": os.path.basename(path),
            "path": path,
            "size_kb": round(size / 1024, 1)
        })
    return frames


def estimate_cost(num_frames, scale, video_info, model="opus"):
    """Estimate token and API cost."""
    est_width = int(video_info["width"] * scale)
    est_height = int(video_info["height"] * scale)
    pixels = est_width * est_height

    # Claude's image token estimation: ~750 tokens per 1000x1000 area
    tokens_per_frame = max(85, int(pixels / 750))
    total_tokens = num_frames * tokens_per_frame

    pricing = {"opus": 15.0, "sonnet": 3.0, "haiku": 0.25}
    rate = pricing.get(model, 15.0)
    cost_usd = (total_tokens / 1_000_000) * rate
    cost_jpy = cost_usd * 150

    return {
        "estimated_resolution": f"{est_width}x{est_height}",
        "tokens_per_frame": tokens_per_frame,
        "total_tokens": total_tokens,
        "estimated_cost_usd": round(cost_usd, 4),
        "estimated_cost_jpy": round(cost_jpy, 1),
        "model": model
    }


def main():
    parser = argparse.ArgumentParser(description="Video frame extractor for Claude Code")
    parser.add_argument("--input", "-i", required=True, help="Input video file path")
    parser.add_argument("--mode", choices=["scene", "similarity", "time"], default="scene",
                        help="Extraction mode (default: scene)")
    parser.add_argument("--threshold", "-t", type=float, default=None,
                        help="Scene threshold (0.0-1.0) or similarity threshold (0.0-1.0)")
    parser.add_argument("--scale", "-s", type=float, default=0.3,
                        help="Scale factor for output images (default: 0.3)")
    parser.add_argument("--quality", "-q", type=int, default=8,
                        help="JPEG quality 1(best)-31(worst) (default: 8)")
    parser.add_argument("--interval", type=float, default=5.0,
                        help="Seconds between frames in time mode (default: 5.0)")
    parser.add_argument("--output-dir", "-o", default=None,
                        help="Output directory (default: auto-generated in /tmp)")
    parser.add_argument("--estimate", action="store_true",
                        help="Only estimate frame count and cost, don't extract")
    parser.add_argument("--model", default="opus", choices=["opus", "sonnet", "haiku"],
                        help="Model for cost estimation (default: opus)")

    args = parser.parse_args()

    if not os.path.isfile(args.input):
        print(json.dumps({"status": "error", "message": f"File not found: {args.input}"}))
        sys.exit(1)

    # Set default threshold based on mode
    if args.threshold is None:
        if args.mode == "scene":
            args.threshold = 0.3
        elif args.mode == "similarity":
            args.threshold = 0.85
        else:
            args.threshold = 0.3

    try:
        video_info = get_video_info(args.input)

        if args.estimate:
            if args.mode == "scene":
                num_frames = estimate_scene_frames(args.input, args.threshold)
            elif args.mode == "similarity":
                # Rough estimate: assume ~15% of total frames are keyframes
                num_frames = max(1, int(video_info["total_frames"] * 0.15))
            else:
                num_frames = max(1, int(video_info["duration_seconds"] / args.interval) + 1)

            cost = estimate_cost(num_frames, args.scale, video_info, args.model)

            result = {
                "status": "estimate",
                "video_info": video_info,
                "estimate": {
                    "mode": args.mode,
                    "threshold": args.threshold,
                    "interval": args.interval if args.mode == "time" else None,
                    "scale": args.scale,
                    "jpeg_quality": args.quality,
                    "estimated_frames": num_frames
                },
                "cost_estimate": cost
            }
        else:
            output_dir = args.output_dir or tempfile.mkdtemp(prefix="video-frames-")

            if args.mode == "scene":
                frames = extract_scene_frames(
                    args.input, output_dir, args.threshold, args.scale, args.quality
                )
                # Warn if scene detection found very few frames
                if len(frames) <= 1:
                    result = {
                        "status": "warning",
                        "message": "Scene detection found only 1 frame. This video may have gradual transitions. Consider using --mode time instead.",
                        "video_info": video_info,
                        "extraction": {
                            "mode": args.mode,
                            "threshold": args.threshold,
                            "scale": args.scale,
                            "jpeg_quality": args.quality,
                            "frames_extracted": len(frames),
                            "output_dir": output_dir,
                            "frames": frames,
                            "total_size_mb": round(sum(f["size_kb"] for f in frames) / 1024, 2)
                        },
                        "cost_estimate": estimate_cost(len(frames), args.scale, video_info, args.model),
                        "suggestion": f"Try: --mode time --interval {max(1, int(video_info['duration_seconds'] / 10))}"
                    }
                    print(json.dumps(result, ensure_ascii=False, indent=2))
                    return
            elif args.mode == "similarity":
                frames = extract_similarity_frames(
                    args.input, output_dir, args.threshold, args.scale, args.quality
                )
            else:
                frames = extract_time_frames(
                    args.input, output_dir, args.interval, args.scale, args.quality
                )

            total_size = sum(f["size_kb"] for f in frames)
            cost = estimate_cost(len(frames), args.scale, video_info, args.model)

            result = {
                "status": "success",
                "video_info": video_info,
                "extraction": {
                    "mode": args.mode,
                    "threshold": args.threshold,
                    "interval": args.interval if args.mode == "time" else None,
                    "scale": args.scale,
                    "jpeg_quality": args.quality,
                    "frames_extracted": len(frames),
                    "output_dir": output_dir,
                    "frames": frames,
                    "total_size_mb": round(total_size / 1024, 2)
                },
                "cost_estimate": cost
            }

        print(json.dumps(result, ensure_ascii=False, indent=2))

    except Exception as e:
        print(json.dumps({"status": "error", "message": str(e)}, ensure_ascii=False))
        sys.exit(1)


if __name__ == "__main__":
    main()
