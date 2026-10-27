// Robust GL client for the lost-context test (patches/mesa-asahi-lost-context-noop.patch).
// Creates a GLES 2 context with LOSE_CONTEXT_ON_RESET (EGL_EXT_create_context_robustness) on the
// surfaceless platform, draws a uniform-coloured triangle into a renderbuffer every frame, and
// checks glGetGraphicsResetStatusEXT after each frame. Run with tests/lost-context-inject.c.
// Prints ROBUST_PASS when it sees the reset and keeps calling GL for 2 s after it without a crash.
// Build: gcc -O2 -o robust-reset-test tests/robust-reset-test.c -lEGL -lGLESv2
// Usage: LD_PRELOAD=./lost-context-inject.so LOST_AFTER_S=3 ./robust-reset-test 15
// ROBUST_ALLOC=1 also creates, fills and deletes a 1024x1024 texture every frame, so the driver
// needs new buffers after the loss (with LOST_SUBMIT=0: the kwin_wayland order of 2026-10-27).
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

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
	return s;
}

int main(int argc, char **argv)
{
	double seconds = argc > 1 ? atof(argv[1]) : 15;
	EGLDisplay dpy = eglGetPlatformDisplay(EGL_PLATFORM_SURFACELESS_MESA, EGL_DEFAULT_DISPLAY, NULL);
	if (!eglInitialize(dpy, NULL, NULL)) { puts("no EGL display\nROBUST_FAIL"); return 1; }
	eglBindAPI(EGL_OPENGL_ES_API);
	EGLint cfg_attr[] = { EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT, EGL_NONE };
	EGLConfig cfg;
	EGLint n = 0;
	eglChooseConfig(dpy, cfg_attr, &cfg, 1, &n);
	EGLint ctx_attr[] = { EGL_CONTEXT_CLIENT_VERSION, 2,
		EGL_CONTEXT_OPENGL_RESET_NOTIFICATION_STRATEGY_EXT, EGL_LOSE_CONTEXT_ON_RESET_EXT, EGL_NONE };
	EGLContext ctx = eglCreateContext(dpy, n ? cfg : EGL_NO_CONFIG_KHR, EGL_NO_CONTEXT, ctx_attr);
	if (ctx == EGL_NO_CONTEXT || !eglMakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, ctx)) {
		printf("no robust context (EGL error %#x)\nROBUST_FAIL\n", eglGetError());
		return 1;
	}
	PFNGLGETGRAPHICSRESETSTATUSEXTPROC status =
		(PFNGLGETGRAPHICSRESETSTATUSEXTPROC)eglGetProcAddress("glGetGraphicsResetStatusEXT");
	if (!status) { puts("no glGetGraphicsResetStatusEXT\nROBUST_FAIL"); return 1; }
	printf("renderer: %s\n", glGetString(GL_RENDERER));

	GLuint rb, fb;
	glGenRenderbuffers(1, &rb);
	glBindRenderbuffer(GL_RENDERBUFFER, rb);
	glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA4, 256, 256);
	glGenFramebuffers(1, &fb);
	glBindFramebuffer(GL_FRAMEBUFFER, fb);
	glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, rb);
	GLuint prog = glCreateProgram();
	glAttachShader(prog, shader(GL_VERTEX_SHADER,
		"attribute vec2 p; uniform float t; void main() { gl_Position = vec4(p * (0.5 + 0.5 * sin(t)), 0.0, 1.0); }"));
	glAttachShader(prog, shader(GL_FRAGMENT_SHADER,
		"precision mediump float; uniform float t; void main() { gl_FragColor = vec4(fract(t), 0.5, 0.2, 1.0); }"));
	glBindAttribLocation(prog, 0, "p");
	glLinkProgram(prog);
	glUseProgram(prog);
	GLint ut = glGetUniformLocation(prog, "t");
	static const float tri[] = { -1, -1, 1, -1, 0, 1 };
	glEnableVertexAttribArray(0);
	glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, tri);

	int alloc = getenv("ROBUST_ALLOC") && atoi(getenv("ROBUST_ALLOC"));
	static unsigned char texels[1024 * 1024 * 4];
	double t0 = now(), reset_at = 0;
	long frames = 0, after = 0;
	GLenum seen = GL_NO_ERROR;
	while (now() - t0 < seconds) {
		glUniform1f(ut, (float)frames * 0.01f);
		glClearColor(0, 0, (float)(frames % 2), 1);
		glClear(GL_COLOR_BUFFER_BIT);
		if (alloc) {
			GLuint tex;
			texels[frames % sizeof(texels)] = (unsigned char)frames;
			glGenTextures(1, &tex);
			glBindTexture(GL_TEXTURE_2D, tex);
			glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 1024, 1024, 0, GL_RGBA, GL_UNSIGNED_BYTE, texels);
			glDrawArrays(GL_TRIANGLES, 0, 3);
			glDeleteTextures(1, &tex);
		} else {
			glDrawArrays(GL_TRIANGLES, 0, 3);
		}
		glFinish();
		frames++;
		if (seen == GL_NO_ERROR) {
			seen = status();
			if (seen != GL_NO_ERROR) {
				reset_at = now();
				printf("reset seen after %ld frames, %.1f s: status %#x\n", frames, reset_at - t0, seen);
			}
		} else if (now() - reset_at > 2) {
			break;
		} else {
			after++;
		}
	}
	printf("frames %ld, GL calls after the reset: %ld frames\n", frames, after);
	puts(seen != GL_NO_ERROR ? "ROBUST_PASS" : "ROBUST_NO_RESET");
	return seen != GL_NO_ERROR ? 0 : 2;
}
