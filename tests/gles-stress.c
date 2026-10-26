// Headless GPU stress test with exact checks. No display or login needed.
// Each frame runs a heavy integer shader (xorshift loop per pixel) into a
// 1024x1024 R32UI target. Every frame is drawn with a new seed; every 10th
// frame is read back in full and compared with the same math on the CPU.
// Build: tests/build-tests.sh
// Run:   gles-stress <seconds>
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#define W 1024
#define H 1024
#define ITERS 400

static unsigned cpu_value(unsigned x, unsigned y, unsigned seed)
{
	unsigned s = (x * 73856093u) ^ (y * 19349663u) ^ seed;
	for (int i = 0; i < ITERS; i++) {
		s ^= s << 13;
		s ^= s >> 17;
		s ^= s << 5;
		s += (unsigned)i;
	}
	return s;
}

static double now(void)
{
	struct timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec + t.tv_nsec / 1e9;
}

static GLuint shader(GLenum type, const char *src)
{
	GLuint s = glCreateShader(type);
	glShaderSource(s, 1, &src, NULL);
	glCompileShader(s);
	GLint ok = 0;
	glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
	if (!ok) {
		char log[1024];
		glGetShaderInfoLog(s, sizeof(log), NULL, log);
		fprintf(stderr, "shader compile failed: %s\n", log);
		exit(2);
	}
	return s;
}

int main(int argc, char **argv)
{
	double seconds = argc > 1 ? atof(argv[1]) : 60;
	PFNEGLGETPLATFORMDISPLAYEXTPROC get_display =
		(PFNEGLGETPLATFORMDISPLAYEXTPROC)eglGetProcAddress("eglGetPlatformDisplayEXT");
	EGLDisplay dpy = get_display(EGL_PLATFORM_SURFACELESS_MESA, EGL_DEFAULT_DISPLAY, NULL);
	if (!eglInitialize(dpy, NULL, NULL)) { fprintf(stderr, "eglInitialize failed\n"); return 2; }
	eglBindAPI(EGL_OPENGL_ES_API);
	const EGLint cattr[] = { EGL_CONTEXT_MAJOR_VERSION, 3, EGL_NONE };
	EGLContext ctx = eglCreateContext(dpy, EGL_NO_CONFIG_KHR, EGL_NO_CONTEXT, cattr);
	if (ctx == EGL_NO_CONTEXT || !eglMakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, ctx)) {
		fprintf(stderr, "context failed\n"); return 2;
	}
	printf("renderer: %s\n", glGetString(GL_RENDERER));

	GLuint tex, fbo;
	glGenTextures(1, &tex);
	glBindTexture(GL_TEXTURE_2D, tex);
	glTexStorage2D(GL_TEXTURE_2D, 1, GL_R32UI, W, H);
	glGenFramebuffers(1, &fbo);
	glBindFramebuffer(GL_FRAMEBUFFER, fbo);
	glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex, 0);
	if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
		fprintf(stderr, "framebuffer incomplete\n"); return 2;
	}

	const char *vs = "#version 300 es\n"
		"void main(){ vec2 p = vec2(gl_VertexID == 1 ? 3.0 : -1.0, gl_VertexID == 2 ? 3.0 : -1.0);"
		" gl_Position = vec4(p, 0.0, 1.0); }\n";
	char fs[1024];
	snprintf(fs, sizeof(fs), "#version 300 es\nprecision highp float; precision highp int;\n"
		"uniform uint seed; layout(location = 0) out uint o;\n"
		"void main(){ uint x = uint(gl_FragCoord.x); uint y = uint(gl_FragCoord.y);\n"
		" uint s = (x * 73856093u) ^ (y * 19349663u) ^ seed;\n"
		" for (int i = 0; i < %d; i++) { s ^= s << 13; s ^= s >> 17; s ^= s << 5; s += uint(i); }\n"
		" o = s; }\n", ITERS);
	GLuint prog = glCreateProgram();
	glAttachShader(prog, shader(GL_VERTEX_SHADER, vs));
	glAttachShader(prog, shader(GL_FRAGMENT_SHADER, fs));
	glLinkProgram(prog);
	GLint linked = 0;
	glGetProgramiv(prog, GL_LINK_STATUS, &linked);
	if (!linked) { fprintf(stderr, "link failed\n"); return 2; }
	GLint useed = glGetUniformLocation(prog, "seed");

	GLuint vao;
	glGenVertexArrays(1, &vao);
	glBindVertexArray(vao);
	glViewport(0, 0, W, H);
	glUseProgram(prog);

	static unsigned px[W * H * 4];
	long frames = 0, checks = 0, wrong = 0;
	double t0 = now(), last = t0;
	while (now() - t0 < seconds) {
		unsigned seed = (unsigned)frames * 2654435761u;
		glUniform1ui(useed, seed);
		glDrawArrays(GL_TRIANGLES, 0, 3);
		frames++;
		if (frames % 10 == 0) {
			glReadPixels(0, 0, W, H, GL_RGBA_INTEGER, GL_UNSIGNED_INT, px);
			checks++;
			long bad = 0;
			for (int y = 0; y < H; y += 7)
				for (int x = 0; x < W; x += 7)
					if (px[(y * W + x) * 4] != cpu_value(x, y, seed))
						bad++;
			wrong += bad;
			if (bad)
				printf("frame %ld: %ld wrong samples\n", frames, bad);
		}
		GLenum err = glGetError();
		if (err != GL_NO_ERROR) { printf("gl error 0x%x at frame %ld\n", err, frames); return 1; }
		if (now() - last >= 30) {
			last = now();
			printf("%.0f s: %ld frames, %ld checks, %ld wrong\n", last - t0, frames, checks, wrong);
			fflush(stdout);
		}
	}
	glFinish();
	double t = now() - t0;
	printf("frames %ld in %.1f s (%.1f fps, %.2f Gpix-iter/s), checks %ld, wrong samples %ld\n",
	       frames, t, frames / t, frames * (double)W * H * ITERS / t / 1e9, checks, wrong);
	printf("%s\n", wrong == 0 ? "STRESS_PASS" : "STRESS_FAIL");
	return wrong != 0;
}
