// Minimal GPU render check: draw a full-screen triangle with a shader into a
// 64x64 offscreen framebuffer, read it back and compare exact pixel values.
// Build: tests/build-tests.sh
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>
#include <stdio.h>
#include <string.h>

#define W 64
#define H 64

static GLuint shader(GLenum type, const char *src)
{
	GLuint s = glCreateShader(type);
	glShaderSource(s, 1, &src, NULL);
	glCompileShader(s);
	GLint ok = 0;
	glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
	if (!ok) {
		char log[512];
		glGetShaderInfoLog(s, sizeof(log), NULL, log);
		fprintf(stderr, "shader compile failed: %s\n", log);
	}
	return s;
}

int main(void)
{
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
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, W, H, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
	glGenFramebuffers(1, &fbo);
	glBindFramebuffer(GL_FRAMEBUFFER, fbo);
	glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex, 0);
	if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
		fprintf(stderr, "framebuffer incomplete\n"); return 2;
	}

	// Left half (x < 32) red, right half green, written per fragment by the shader.
	const char *vs = "#version 300 es\n"
		"void main(){ vec2 p = vec2(gl_VertexID == 1 ? 3.0 : -1.0, gl_VertexID == 2 ? 3.0 : -1.0);"
		" gl_Position = vec4(p, 0.0, 1.0); }\n";
	const char *fs = "#version 300 es\nprecision highp float;\nout vec4 c;\n"
		"void main(){ c = gl_FragCoord.x < 32.0 ? vec4(1,0,0,1) : vec4(0,1,0,1); }\n";
	GLuint prog = glCreateProgram();
	glAttachShader(prog, shader(GL_VERTEX_SHADER, vs));
	glAttachShader(prog, shader(GL_FRAGMENT_SHADER, fs));
	glLinkProgram(prog);
	GLint linked = 0;
	glGetProgramiv(prog, GL_LINK_STATUS, &linked);
	if (!linked) { fprintf(stderr, "link failed\n"); return 2; }

	GLuint vao;
	glGenVertexArrays(1, &vao);
	glBindVertexArray(vao);
	glViewport(0, 0, W, H);
	glClearColor(0, 0, 1, 1);
	glClear(GL_COLOR_BUFFER_BIT);
	glUseProgram(prog);
	glDrawArrays(GL_TRIANGLES, 0, 3);

	static unsigned char px[W * H * 4];
	glReadPixels(0, 0, W, H, GL_RGBA, GL_UNSIGNED_BYTE, px);
	GLenum err = glGetError();

	int bad = 0;
	for (int y = 0; y < H; y++)
		for (int x = 0; x < W; x++) {
			const unsigned char *p = &px[(y * W + x) * 4];
			unsigned char want[4] = { x < 32 ? 255 : 0, x < 32 ? 0 : 255, 0, 255 };
			if (memcmp(p, want, 4))
				bad++;
		}
	printf("gl error: 0x%x, wrong pixels: %d of %d\n", err, bad, W * H);
	printf("%s\n", (bad == 0 && err == GL_NO_ERROR) ? "READBACK_PASS" : "READBACK_FAIL");
	return bad || err;
}
