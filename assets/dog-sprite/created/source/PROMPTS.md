# Image generation prompts

Mode: built-in image_gen.

## Shiba master

Use case: stylized-concept
Asset type: production pixel-art animation sprite sheet for a tiny macOS desktop pet.
Primary request: Create an original adorable orange-and-cream SHIBA INU running dog, in EIGHT consecutive frames of a fluid side-view gallop, facing RIGHT.
Composition: exactly 4 columns by 2 rows of equally sized square cells in a square 1024x1024 image. Exactly one same-sized dog per cell, fully contained with clear empty padding. Read order left to right then top to bottom. Each cell represents a 48x48 logical pixel canvas, enlarged with hard square pixel edges. Torso center aligned identically across all cells; natural vertical bob of only one logical pixel. Body extends about 32 logical pixels horizontally. Keep face, body volume, ears, tail and markings perfectly consistent.
Character: appealing chubby shiba, rich amber orange back, warm cream cheeks and muzzle and chest, small triangular ears, full curled tail above rump, shiny dark eye, dark button nose, cheerful mouth, tiny pink tongue, short but clearly articulated legs. Strong readable silhouette, dark brown one-logical-pixel outline, tasteful flat 8-color pixel palette, shaded far legs to distinguish four legs. Professional handcrafted 16-bit game sprite quality.
Animation poses: 1 forepaws reaching forward and hind paws stretched backward airborne; 2 leading front paw landing; 3 front paws bearing weight, chest lowered, hind legs swing forward; 4 legs gathered underneath belly with bent joints; 5 hind feet land forward under belly while front legs curl back; 6 hind legs push off backwards and front legs reach forward; 7 full airborne extension with separated pairs of paws; 8 flight preparing front-paw contact, smoothly connecting back to 1. Real running motion not eight static duplicates. Torso and head stay rigid except restrained bounce, motion primarily in articulated legs. No horizontal camera shift.
Background: genuinely TRANSPARENT alpha, no checkerboard painted into image.
Constraints: no labels, no text, no grid lines, no ground, no shadow, no scenery, no motion streaks, no anti-aliasing, no gradients, no blur. Clean transparent sprite sheet only.

## Corgi master

Reference: the generated shiba master (`shiba.png`).

Use case: precise-object-edit
Asset type: companion pixel-art running dog sprite sheet for Meetie.
Input image: reference sheet of eight running shiba sprites.
Primary request: Create the matching WELSH CORGI breed version of this eight-frame running animation. Change the dog breed in every frame to a low-slung corgi with longer body and short articulated legs, warm golden-tan coat, white muzzle/chest/socks, distinctive white blaze up face, oversized upright rounded ears, tiny nub tail instead of a curled tail. Keep the cheerful eye and happy mouth with little pink tongue.
Invariants: exactly eight dogs facing RIGHT, arranged in FOUR columns and TWO rows in the same pose order, consistent scale, identical character across all frames, same professional 16-bit pixel art look and dark one-logical-pixel outline. Preserve distinct gallop poses, including extended flight, forepaw landing, gathered bent legs, hind leg drive, and flight.
Layout: square 1024x1024 canvas, equally spaced cells, clear transparent padding around every dog and outer edges. No dog touching cell boundaries. True alpha transparency.
Constraints: no checkerboard background, no labels or text, no grid, no ground or shadows, no blur or soft edges or gradient shading. Crisp limited-palette pixel clusters.

