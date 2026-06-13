import cv2
import numpy as np

def find_headers(page_num, num_surahs):
    img_path = f"c:/Users/Mahfod501/Desktop/flutter/quran/quran_app/assets/images/page_{page_num}.webp"
    img = cv2.imread(img_path, cv2.IMREAD_GRAYSCALE)
    
    # Let's crop a slice from the middle since headers are centered and wide
    # The header is usually the most complex part.
    # We can use the template we saved before, or we can just look for horizontal bands that have no text (Bismillah) below them
    
    # Actually, the template matching was working well for other pages.
    template = cv2.imread("c:/Users/Mahfod501/.gemini/antigravity/brain/00848258-0c85-444f-90c1-39b459273988/scratch/header_crop.png", cv2.IMREAD_GRAYSCALE)
    if template is None:
        print("Template missing")
        return
        
    res = cv2.matchTemplate(img, template, cv2.TM_CCOEFF_NORMED)
    
    # We need to find exactly `num_surahs` peaks.
    threshold = 0.15 # lower threshold
    loc = np.where(res >= threshold)
    
    peaks = []
    for pt in zip(*loc[::-1]):
        y = pt[1]
        # Check if this y is far enough from existing peaks
        is_new = True
        for p in peaks:
            if abs(y - p) < 100: # within 100 pixels is the same header
                is_new = False
                break
        if is_new:
            peaks.append(y)
            
    peaks.sort()
    
    # If we found more peaks than num_surahs, just take the top matches
    # Let's get the values of the peaks
    peak_vals = []
    for y in peaks:
        x_idx = np.argmax(res[y, :])
        peak_vals.append((y, res[y, x_idx]))
        
    peak_vals.sort(key=lambda x: x[1], reverse=True)
    best_peaks = [p[0] for p in peak_vals[:num_surahs]]
    best_peaks.sort()
    
    ratios = [round(y / img.shape[0], 3) for y in best_peaks]
    
    # If a page has a Surah at the top, it might not have the full decorative header, or it might just be Y=0.
    # Let's just print them
    print(f"Page {page_num}: Found {len(peaks)} peaks above {threshold}. Top {num_surahs} are: {ratios}")

find_headers(596, 2)
find_headers(597, 2)
find_headers(598, 2)
find_headers(599, 3)
find_headers(600, 3)
find_headers(601, 3)
find_headers(602, 3)
