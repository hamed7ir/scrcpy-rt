/*
 * sdlcanary -- BATCH-SCRCPY-2 section 2.3.  REV 2.
 *
 * THE GATE. Nothing of scrcpy is compiled until this has run on the Surface RT.
 *
 * WHY REV 2 EXISTS
 * Rev 1 ran on the Surface RT and printed PASS: direct3d11 and direct3d both created, an IYUV
 * streaming texture created, "120/120 frames presented", 103.1 fps, WASAPI open.
 * Someone watched the actual screen and reported THE WINDOW WAS BLACK.
 *
 * Rev 1 could not have known. It never checked the return value of SDL_RenderClear,
 * SDL_RenderTexture or SDL_RenderPresent, so "120/120 frames presented" could equally have been
 * 120 no-ops, and the fps figure could have been timing an upload into a texture that was never
 * drawn. A renderer that CREATES is not a renderer that DRAWS -- the same distinction rev 1 made
 * loudly about "compiled in != works", one layer further down, and I missed it there.
 *
 * Tegra 3 is Direct3D feature level 9_1. SDL's D3D11 renderer converts YUV in a pixel shader,
 * and ps_4_0_level_9_1 is a restricted profile. Whether that path works here is exactly what
 * scrcpy's video output depends on, because scrcpy uploads every decoded frame as IYUV.
 *
 * WHAT REV 2 DOES DIFFERENTLY (step 5):
 *   - tests EVERY driver, not just the default one
 *   - tests IYUV *and* ARGB8888. If ARGB draws and IYUV does not, the YUV shader is the fault,
 *     not the renderer. That is a control, not a second test.
 *   - checks the bool return of every single call, and prints SDL_GetError() on the first failure
 *   - clears to BLUE, fills the texture with mid-GREY, then READS THE FRAMEBUFFER BACK and
 *     prints the centre pixel. Three outcomes, each unambiguous:
 *         grey  -> the texture was drawn. It works.
 *         blue  -> the clear worked, the texture did NOT draw.
 *         black -> neither worked; nothing reached the framebuffer.
 *     A log that says "grey" is a log that cannot be contradicted by looking at the screen.
 *
 * EXIT CODES:
 *   0  a HARDWARE driver drew IYUV correctly            -- the gate is open for real
 *   1  only "software" drew IYUV correctly              -- project continues, slower
 *   2  no driver drew IYUV, or no renderer at all       -- stop and report
 */

#include <stdio.h>
#include <string.h>
#include <windows.h>

#include <SDL3/SDL.h>

#define CANARY_W 800
#define CANARY_H 480
#define FRAMES   120
#define KEY_TIMEOUT_MS 20000
#define GREY 128

static int is_hardware_driver(const char *name)
{
	return name && strcmp(name, "software") != 0;
}

/* classify the centre pixel we read back out of the framebuffer */
static const char *classify(int r, int g, int b)
{
	if (r > 88 && r < 168 && g > 88 && g < 168 && b > 88 && b < 168)
		return "GREY  -> the texture WAS DRAWN. this path works.";
	if (b > 190 && r < 70 && g < 70)
		return "BLUE  -> clear worked, the TEXTURE DID NOT DRAW.";
	if (r < 30 && g < 30 && b < 30)
		return "BLACK -> nothing reached the framebuffer at all.";
	return "other -> unexpected; report the numbers.";
}

/*
 * Draw one frame of `fmt` through `ren`, check every call, and read the result back.
 * Returns 1 if the texture demonstrably drew, 0 otherwise.
 */
static int test_format(SDL_Renderer *ren, SDL_PixelFormat fmt, const char *fmtname,
                       unsigned char *yplane, unsigned char *uplane, unsigned char *vplane,
                       unsigned char *rgba, double *fps_out)
{
	SDL_Texture *tex;
	SDL_Surface *shot;
	Uint8 r = 0, g = 0, b = 0, a = 0;
	Uint64 t0, t1, freq;
	int f, drew = 0;
	double secs;

	*fps_out = 0.0;

	SDL_ClearError();
	tex = SDL_CreateTexture(ren, fmt, SDL_TEXTUREACCESS_STREAMING, CANARY_W, CANARY_H);
	if (!tex) {
		printf("      %-10s CreateTexture FAILED -- %s\n", fmtname, SDL_GetError());
		return 0;
	}

	if (fmt == SDL_PIXELFORMAT_IYUV) {
		if (!SDL_UpdateYUVTexture(tex, NULL, yplane, CANARY_W,
		                          uplane, CANARY_W / 2, vplane, CANARY_W / 2)) {
			printf("      %-10s UpdateYUVTexture FAILED -- %s\n", fmtname, SDL_GetError());
			SDL_DestroyTexture(tex);
			return 0;
		}
	} else {
		if (!SDL_UpdateTexture(tex, NULL, rgba, CANARY_W * 4)) {
			printf("      %-10s UpdateTexture FAILED -- %s\n", fmtname, SDL_GetError());
			SDL_DestroyTexture(tex);
			return 0;
		}
	}

	/* blue clear, so "cleared but not drawn" is distinguishable from "nothing happened" */
	if (!SDL_SetRenderDrawColor(ren, 0, 0, 255, 255))
		printf("      %-10s SetRenderDrawColor FAILED -- %s\n", fmtname, SDL_GetError());
	if (!SDL_RenderClear(ren))
		printf("      %-10s RenderClear FAILED -- %s\n", fmtname, SDL_GetError());
	if (!SDL_RenderTexture(ren, tex, NULL, NULL))
		printf("      %-10s RenderTexture FAILED -- %s\n", fmtname, SDL_GetError());

	/* read the framebuffer BEFORE presenting -- this is the thing rev 1 could not do */
	SDL_ClearError();
	shot = SDL_RenderReadPixels(ren, NULL);
	if (!shot) {
		printf("      %-10s RenderReadPixels FAILED -- %s\n", fmtname, SDL_GetError());
		printf("                 (cannot prove what is on screen; LOOK AT THE WINDOW)\n");
	} else {
		if (!SDL_ReadSurfacePixel(shot, CANARY_W / 2, CANARY_H / 2, &r, &g, &b, &a)) {
			printf("      %-10s ReadSurfacePixel FAILED -- %s\n", fmtname, SDL_GetError());
		} else {
			printf("      %-10s centre pixel rgb(%3u,%3u,%3u)  %s\n",
			       fmtname, r, g, b, classify(r, g, b));
			if (r > 88 && r < 168 && g > 88 && g < 168 && b > 88 && b < 168)
				drew = 1;
		}
		SDL_DestroySurface(shot);
	}

	if (!SDL_RenderPresent(ren))
		printf("      %-10s RenderPresent FAILED -- %s\n", fmtname, SDL_GetError());

	/* now time it, so the fps figure belongs to a path we have just proven or disproven */
	freq = SDL_GetPerformanceFrequency();
	t0 = SDL_GetPerformanceCounter();
	for (f = 0; f < FRAMES; f++) {
		SDL_Event ev;
		if (fmt == SDL_PIXELFORMAT_IYUV) {
			SDL_memset(yplane, (unsigned char)(GREY + ((f & 7) - 4)),
			           (size_t)CANARY_W * CANARY_H);
			SDL_UpdateYUVTexture(tex, NULL, yplane, CANARY_W,
			                     uplane, CANARY_W / 2, vplane, CANARY_W / 2);
		} else {
			SDL_UpdateTexture(tex, NULL, rgba, CANARY_W * 4);
		}
		SDL_RenderClear(ren);
		SDL_RenderTexture(ren, tex, NULL, NULL);
		SDL_RenderPresent(ren);
		while (SDL_PollEvent(&ev)) { }
	}
	t1 = SDL_GetPerformanceCounter();
	secs = (double)(t1 - t0) / (double)freq;
	*fps_out = (secs > 0.0) ? ((double)FRAMES / secs) : 0.0;
	printf("      %-10s %d frames in %.3f s = %.1f fps%s\n",
	       fmtname, FRAMES, secs, *fps_out,
	       drew ? "" : "   <-- of a path that DID NOT DRAW; the number is meaningless");

	SDL_DestroyTexture(tex);
	return drew;
}

int main(int argc, char *argv[])
{
	SDL_Window *win = NULL;
	SDL_Renderer *ren = NULL;
	SDL_AudioStream *astream = NULL;
	SDL_AudioSpec aspec;
	SDL_Event ev;
	unsigned char *yplane = NULL, *uplane = NULL, *vplane = NULL, *rgba = NULL;
	const char *chosen = NULL;
	char iyuv_ok_names[256];
	int ndrv, i, hw_create = 0, sw_create = 0, rc = 2;
	int hw_drew = 0, sw_drew = 0;
	int version;
	size_t n;

	(void)argc; (void)argv;

	SetErrorMode(SEM_NOGPFAULTERRORBOX | SEM_FAILCRITICALERRORS);
	setvbuf(stdout, NULL, _IONBF, 0);
	iyuv_ok_names[0] = '\0';

	printf("sdlcanary REV 2 -- BATCH-SCRCPY-2 section 2.3\n");
	printf("================================================================\n");

	version = SDL_GetVersion();
	printf("SDL_GetVersion()      : %d.%d.%d\n",
	       SDL_VERSIONNUM_MAJOR(version), SDL_VERSIONNUM_MINOR(version),
	       SDL_VERSIONNUM_MICRO(version));
	printf("SDL_GetRevision()     : %s\n", SDL_GetRevision());

	if (!SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO)) {
		printf("SDL_Init              : FAILED -- %s\n", SDL_GetError());
		printf("\nVERDICT: FAIL -- SDL will not initialise.\n");
		return 2;
	}
	printf("SDL_Init              : OK\n");
	printf("video driver in use   : %s\n", SDL_GetCurrentVideoDriver());

	/* ---- step 1 ---- */
	printf("\n--- step 1: render drivers COMPILED IN ---\n");
	ndrv = SDL_GetNumRenderDrivers();
	printf("SDL_GetNumRenderDrivers() = %d\n", ndrv);
	for (i = 0; i < ndrv; i++)
		printf("  [%d] %s\n", i, SDL_GetRenderDriver(i));
	if (ndrv <= 0) {
		printf("\nVERDICT: FAIL -- no render drivers compiled in.\n");
		SDL_Quit();
		return 2;
	}

	/* ---- step 2 ---- */
	printf("\n--- step 2: SDL_CreateWindow ---\n");
	win = SDL_CreateWindow("sdlcanary", CANARY_W, CANARY_H, 0);
	if (!win) {
		printf("SDL_CreateWindow      : FAILED -- %s\n", SDL_GetError());
		SDL_Quit();
		return 2;
	}
	printf("SDL_CreateWindow      : OK (%dx%d)\n", CANARY_W, CANARY_H);

	/* ---- the test pixels: mid-grey in both colour spaces ---- */
	yplane = (unsigned char *)SDL_malloc((size_t)CANARY_W * CANARY_H);
	uplane = (unsigned char *)SDL_malloc((size_t)(CANARY_W / 2) * (CANARY_H / 2));
	vplane = (unsigned char *)SDL_malloc((size_t)(CANARY_W / 2) * (CANARY_H / 2));
	rgba   = (unsigned char *)SDL_malloc((size_t)CANARY_W * CANARY_H * 4);
	if (!yplane || !uplane || !vplane || !rgba) {
		printf("\nVERDICT: FAIL -- could not allocate the test planes.\n");
		SDL_DestroyWindow(win);
		SDL_Quit();
		return 2;
	}
	SDL_memset(yplane, GREY, (size_t)CANARY_W * CANARY_H);
	SDL_memset(uplane, 128,  (size_t)(CANARY_W / 2) * (CANARY_H / 2));
	SDL_memset(vplane, 128,  (size_t)(CANARY_W / 2) * (CANARY_H / 2));
	for (n = 0; n < (size_t)CANARY_W * CANARY_H * 4; n++)
		rgba[n] = ((n & 3) == 3) ? 255 : GREY;     /* opaque mid-grey */

	/* ---- steps 3 and 5, together, per driver ---- */
	printf("\n--- steps 3+5: EVERY driver -- create it, then PROVE it draws ---\n");
	printf("    clear = BLUE, texture = mid-GREY, framebuffer read back after drawing.\n");
	for (i = 0; i < ndrv; i++) {
		const char *name = SDL_GetRenderDriver(i);
		SDL_Renderer *r;
		double fps_yuv = 0.0, fps_rgb = 0.0;
		int yuv_drew, rgb_drew;

		printf("\n  [%s]\n", name);
		SDL_ClearError();
		r = SDL_CreateRenderer(win, name);
		if (!r) {
			printf("      CreateRenderer FAILED -- %s\n", SDL_GetError());
			continue;
		}
		printf("      CreateRenderer OK\n");
		if (is_hardware_driver(name)) hw_create++; else sw_create++;

		/* DETECTOR SELF-TEST, per driver. Clear to blue and deliberately DO NOT draw the
		 * texture. The readback must come back BLUE. If it does not -- if this driver's
		 * RenderReadPixels reads some other buffer, or reads nothing -- then every
		 * "GREY -> the texture WAS DRAWN" printed below it is worthless. Proving the
		 * instrument fires in the FAILING direction is the whole point; rev 1 shipped a
		 * detector that had only ever been seen to pass. */
		{
			SDL_Surface *probe;
			Uint8 pr = 0, pg = 0, pb = 0, pa = 0;
			SDL_SetRenderDrawColor(r, 0, 0, 255, 255);
			SDL_RenderClear(r);
			probe = SDL_RenderReadPixels(r, NULL);
			if (!probe) {
				printf("      SELF-TEST   RenderReadPixels FAILED -- %s\n", SDL_GetError());
				printf("                  ^ this driver cannot be checked. LOOK AT THE WINDOW.\n");
			} else {
				SDL_ReadSurfacePixel(probe, CANARY_W / 2, CANARY_H / 2, &pr, &pg, &pb, &pa);
				SDL_DestroySurface(probe);
				if (pb > 190 && pr < 70 && pg < 70) {
					printf("      SELF-TEST   cleared-but-not-drawn reads rgb(%3u,%3u,%3u) = BLUE. detector OK.\n",
					       pr, pg, pb);
				} else {
					printf("      SELF-TEST   FAILED: expected BLUE, got rgb(%3u,%3u,%3u).\n",
					       pr, pg, pb);
					printf("                  ^ the readback does not reflect this renderer.\n");
					printf("                    TREAT EVERY RESULT BELOW FOR THIS DRIVER AS UNPROVEN.\n");
				}
			}
		}

		/* ARGB first: the control. If this draws and IYUV does not, it is the YUV path. */
		rgb_drew = test_format(r, SDL_PIXELFORMAT_ARGB8888, "ARGB8888",
		                       yplane, uplane, vplane, rgba, &fps_rgb);
		yuv_drew = test_format(r, SDL_PIXELFORMAT_IYUV, "IYUV",
		                       yplane, uplane, vplane, rgba, &fps_yuv);

		if (yuv_drew) {
			if (iyuv_ok_names[0]) SDL_strlcat(iyuv_ok_names, ", ", sizeof(iyuv_ok_names));
			SDL_strlcat(iyuv_ok_names, name, sizeof(iyuv_ok_names));
			if (is_hardware_driver(name)) hw_drew++; else sw_drew++;
		}
		if (rgb_drew && !yuv_drew)
			printf("      ==> ARGB draws but IYUV does not: the YUV conversion path is the fault,\n"
			       "          not the renderer. scrcpy uploads IYUV, so this driver is unusable\n"
			       "          for it as-is.\n");
		if (!rgb_drew && !yuv_drew)
			printf("      ==> nothing draws through this driver at all.\n");

		SDL_DestroyRenderer(r);
	}

	/* ---- step 4: what scrcpy actually gets ---- */
	printf("\n--- step 4: SDL_CreateRenderer(window, NULL) -- what scrcpy calls ---\n");
	SDL_ClearError();
	ren = SDL_CreateRenderer(win, NULL);
	if (ren) {
		chosen = SDL_GetRendererName(ren);
		printf("chosen driver         : %s\n", chosen ? chosen : "(unnamed)");
	} else {
		printf("SDL_CreateRenderer(NULL): FAILED -- %s\n", SDL_GetError());
	}

	/* ---- step 6: audio ---- */
	printf("\n--- step 6: SDL_OpenAudioDeviceStream, SDL_AUDIO_F32LE ---\n");
	SDL_zero(aspec);
	aspec.format = SDL_AUDIO_F32LE;
	aspec.channels = 2;
	aspec.freq = 48000;
	SDL_ClearError();
	astream = SDL_OpenAudioDeviceStream(SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, &aspec, NULL, NULL);
	if (astream) {
		printf("SDL_OpenAudioDeviceStream: SUCCESS\n");
		printf("audio driver in use   : %s\n", SDL_GetCurrentAudioDriver());
		SDL_DestroyAudioStream(astream);
	} else {
		printf("SDL_OpenAudioDeviceStream: FAILED -- %s\n", SDL_GetError());
		printf("  ^ not fatal; the first scrcpy run uses --no-audio anyway.\n");
	}

	/* ---- step 7 ---- */
	printf("\n--- step 7: press any key (20 s timeout) ---\n");
	{
		Uint64 start = SDL_GetTicks();
		int got = 0;
		while (SDL_GetTicks() - start < (Uint64)KEY_TIMEOUT_MS) {
			while (SDL_PollEvent(&ev)) {
				if (ev.type == SDL_EVENT_KEY_DOWN) {
					printf("key pressed           : keycode 0x%08X  scancode %d  name '%s'\n",
					       (unsigned)ev.key.key, (int)ev.key.scancode,
					       SDL_GetKeyName(ev.key.key));
					got = 1;
					break;
				}
				if (ev.type == SDL_EVENT_QUIT) {
					printf("window closed instead of a key press\n");
					got = 1;
					break;
				}
			}
			if (got) break;
			SDL_Delay(10);
		}
		if (!got)
			printf("no key in 20 s        : TIMEOUT (not a failure; record it)\n");
	}

	/* ---- verdict ---- */
	printf("\n--- verdict ---\n");
	printf("render drivers compiled in     : %d\n", ndrv);
	printf("renderers that CREATED         : %d hardware, %d software\n", hw_create, sw_create);
	printf("drivers that actually DREW IYUV: %s\n", iyuv_ok_names[0] ? iyuv_ok_names : "(none)");
	printf("driver chosen by SDL default   : %s\n", chosen ? chosen : "(none)");

	if (hw_drew > 0) {
		printf("\nVERDICT: PASS -- a HARDWARE driver draws IYUV. The SCRCPY-2 gate is open.\n");
		printf("         Use --render-driver=<one of: %s>\n", iyuv_ok_names);
		rc = 0;
	} else if (sw_drew > 0) {
		printf("\nVERDICT: SOFTWARE ONLY -- only the software renderer draws IYUV.\n");
		printf("         scrcpy will work but slower. Use --render-driver=software and\n");
		printf("         start at a smaller --max-size.\n");
		rc = 1;
	} else {
		printf("\nVERDICT: FAIL -- no driver drew IYUV. Read the per-driver lines above:\n");
		printf("         if ARGB8888 drew anywhere, the YUV conversion is the problem.\n");
		rc = 2;
	}

	if (yplane) SDL_free(yplane);
	if (uplane) SDL_free(uplane);
	if (vplane) SDL_free(vplane);
	if (rgba)   SDL_free(rgba);
	if (ren) SDL_DestroyRenderer(ren);
	if (win) SDL_DestroyWindow(win);
	SDL_Quit();
	return rc;
}
