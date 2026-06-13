import cv2
import numpy as np
import sys
import glob

def find_surahs(page_num, num_surahs):
    img_path = f"c:/Users/Mahfod501/Desktop/flutter/quran/quran_app/assets/images/page_{page_num}.webp"
    img = cv2.imread(img_path, cv2.IMREAD_GRAYSCALE)
    if img is None:
        print(f"Error loading {img_path}")
        return

    # Edge detection approach to find horizontal lines of the surah frame
    edges = cv2.Canny(img, 50, 150)
    
    # Calculate horizontal projection (sum along columns)
    proj = np.sum(edges, axis=1)
    
    # We expect high spikes where the decorative frame borders are
    # Find peaks manually
    mean_val = np.mean(proj)
    std_val = np.std(proj)
    threshold = mean_val + std_val
    
    peaks = []
    for i in range(1, len(proj) - 1):
        if proj[i] > threshold and proj[i] > proj[i-1] and proj[i] > proj[i+1]:
            peaks.append(i)
    
    # For a surah header, we usually have a thick decorative band. 
    # Let's group peaks that are close to each other.
    groups = []
    current_group = []
    for p in peaks:
        if not current_group:
            current_group.append(p)
        elif p - current_group[-1] < 50:
            current_group.append(p)
        else:
            groups.append(np.mean(current_group))
            current_group = [p]
    if current_group:
        groups.append(np.mean(current_group))
        
    print(f"Page {page_num}: Found {len(groups)} potential headers at {groups}")
    
    # We want exactly `num_surahs` headers. If we have more, we take the top ones with highest energy?
    # Actually, let's just print them out.
    ratios = [round(g / img.shape[0], 3) for g in groups]
    print(f"  Ratios: {ratios}")

find_surahs(596, 2)
find_surahs(597, 2)
find_surahs(598, 2)
find_surahs(599, 3)
find_surahs(600, 3)
find_surahs(601, 3)
find_surahs(602, 3)
