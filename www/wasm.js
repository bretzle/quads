"use strict"

const quads = {
    module: undefined,
    canvas: undefined,
    events: [],
    gl: WebGL2RenderingContext = undefined,
    objects: [,],
    uniforms: [],

    log: "",

    start(module, canvas) {
        quads.module = module;
        quads.canvas = canvas;

        module.exports._start();
        requestAnimationFrame(quads.loop);

        if (canvas.style.width === "") canvas.style.width = `${canvas.scrollWidth}px`;
        if (canvas.style.height === "") canvas.style.height = `${canvas.scrollHeight}px`;
        new ResizeObserver(() => quads.resize()).observe(canvas);

        quads.resize();
        quads.events.push(1);

        canvas.addEventListener("contextmenu", event => event.preventDefault());
        canvas.addEventListener("focus", () => quads.events.push(2));
        canvas.addEventListener("blur", () => quads.events.push(3));
        canvas.addEventListener("keydown", event => {
            event.preventDefault();
            const key = quads.keys[event.code];
            if (key) quads.events.push(10, key);
            if ([...event.key].length == 1) quads.events.push(9, event.key.codePointAt(0));
        });
        canvas.addEventListener("keyup", event => {
            const key = quads.keys[event.code];
            if (key) quads.events.push(11, key);
        });
        canvas.addEventListener("mousedown", event => {
            const button = quads.buttons[event.button];
            if (button != undefined) quads.events.push(10, button);
        });
        canvas.addEventListener("mouseup", event => {
            const button = quads.buttons[event.button];
            if (button != undefined) quads.events.push(11, button);
        });
        canvas.addEventListener("mousemove", event => {
            quads.events.push(12, event.offsetX, event.offsetY);
        });
        canvas.addEventListener("wheel", event => {
            if (event.deltaY != 0) quads.events.push(14, event.deltaY * 0.01);
            if (event.deltaX != 0) quads.events.push(15, event.deltaX * 0.01);
        });
    },

    loop() {
        if (quads.module.exports.quadsLoop()) {
            requestAnimationFrame(quads.loop);
        }
    },

    resize() {
        const width = parseInt(canvas.style.width);
        const height = parseInt(canvas.style.height);
        canvas.width = width * devicePixelRatio;
        canvas.height = height * devicePixelRatio;
        quads.events.push(
            5, width, height,
            6, canvas.width, canvas.height,
            7, devicePixelRatio,
        );
    },

    // imports

    write(ptr, len) {
        quads.log += quads.getString(ptr, len);
    },

    flush() {
        console.log(quads.log);
        quads.log = "";
    },

    createContext() {
        quads.gl = quads.canvas.getContext("webgl2")
    },

    shift() {
        return quads.events.shift();
    },

    shiftFloat() {
        return quads.events.shift();
    },

    // helpers

    getString(ptr, len) {
        return new TextDecoder().decode(new Uint8Array(quads.module.exports.memory.buffer, ptr, len));
    },

    getStringZ(ptr) {
        const array = new Uint8Array(quads.module.exports.memory.buffer, ptr);
        let len = 0;
        while (array[len]) len++;
        return new TextDecoder().decode(array.subarray(0, len));
    },

    setStringZ(ptr, max, length, string) {
        const buffer = new Uint8Array(quads.module.exports.memory.buffer, ptr);
        const result = new TextEncoder().encodeInto(string, buffer.subarray(0, max - 1));
        buffer[result.written] = 0;
        if (length != 0) {
            new Int32Array(quads.module.exports.memory.buffer, length)[0] = result.written;
        }
    },

    setParams(Array, ptr, value) {
        const buffer = new Array(quads.module.exports.memory.buffer, ptr);
        if (typeof value == "function") {
            buffer.set(value);
        } else {
            buffer[0] = value;
        }
    },

    pushObject(object) {
        const index = quads.objects.indexOf(null);
        if (index != -1) {
            quads.objects[index] = object;
            return index;
        } else {
            return quads.objects.push(object) - 1;
        }
    },

    // gl

    glActiveTexture(texture) {
        quads.gl.activeTexture(texture);
    },

    glAttachShader(program, shader) {
        quads.gl.attachShader(quads.objects[program], quads.objects[shader]);
    },

    glBindAttribLocation(program, index, name) {
        quads.gl.bindAttribLocation(quads.objects[program], index, quads.getStringZ(name));
    },

    glBindBuffer(target, buffer) {
        quads.gl.bindBuffer(target, quads.objects[buffer]);
    },

    glBindVertexArray(vao) {
        quads.gl.bindVertexArray(quads.objects[vao]);
    },

    glBindFramebuffer(target, framebuffer) {
        quads.gl.bindFramebuffer(target, framebuffer ? quads.objects[framebuffer] : null);
    },

    glBindRenderbuffer(target, renderbuffer) {
        quads.gl.bindRenderbuffer(target, quads.objects[renderbuffer]);
    },

    glBindTexture(target, texture) {
        quads.gl.bindTexture(target, quads.objects[texture]);
    },

    glBlendColor(red, green, blue, alpha) {
        quads.gl.blendColor(red, green, blue, alpha);
    },

    glBlendEquation(mode) {
        quads.gl.blendEquation(mode);
    },

    glBlendEquationSeparate(modeRGB, modeAlpha) {
        quads.gl.blendEquationSeparate(modeRGB, modeAlpha);
    },

    glBlendFunc(sfactor, dfactor) {
        quads.gl.blendFunc(sfactor, dfactor);
    },

    glBlendFuncSeparate(srcRGB, dstRGB, srcAlpha, dstAlpha) {
        quads.gl.blendFuncSeparate(srcRGB, dstRGB, srcAlpha, dstAlpha);
    },

    glBufferData(target, size, data, usage) {
        quads.gl.bufferData(target, new Uint8Array(quads.module.exports.memory.buffer, data, size), usage);
    },

    glBufferSubData(target, offset, size, data) {
        quads.gl.bufferSubData(target, offset, new Uint8Array(quads.module.exports.memory.buffer, data, size));
    },

    glCheckFramebufferStatus(target) {
        return quads.gl.checkFramebufferStatus(target);
    },

    glClear(mask) {
        quads.gl.clear(mask);
    },

    glClearColor(red, green, blue, alpha) {
        quads.gl.clearColor(red, green, blue, alpha);
    },

    glClearDepthf(depth) {
        quads.gl.clearDepth(depth);
    },

    glClearStencil(s) {
        quads.gl.clearStencil(s);
    },

    glColorMask(red, green, blue, alpha) {
        quads.gl.colorMask(red, green, blue, alpha);
    },

    glCompileShader(shader) {
        quads.gl.compileShader(quads.objects[shader]);
    },

    glCompressedTexImage2D(target, level, internalformat, width, height, border, imageSize, data) {
        quads.gl.compressedTexImage2D(target, level, internalformat, width, height, border, new Uint8Array(quads.module.exports.memory.buffer, data, imageSize));
    },

    glCompressedTexSubImage2D(target, level, xoffset, yoffset, width, height, format, imageSize, data) {
        quads.gl.compressedTexSubImage2D(target, level, xoffset, yoffset, width, height, format, new Uint8Array(quads.module.exports.memory.buffer, data, imageSize));
    },

    glCopyTexImage2D(target, level, internalformat, x, y, width, height, border) {
        quads.gl.copyTexImage2D(target, level, internalformat, x, y, width, height, border);
    },

    glCopyTexSubImage2D(target, level, xoffset, yoffset, x, y, width, height) {
        quads.gl.copyTexSubImage2D(target, level, xoffset, yoffset, x, y, width, height);
    },

    glCreateProgram() {
        const program = quads.gl.createProgram();
        return quads.pushObject(program);
    },

    glCreateShader(type) {
        const shader = quads.gl.createShader(type);
        return quads.pushObject(shader);
    },

    glCullFace(mode) {
        quads.gl.cullFace(mode);
    },

    glDeleteBuffers(n, ptr) {
        const buffers = new Uint32Array(quads.module.exports.memory.buffer, ptr, n);
        for (let i = 0; i < n; i++) {
            quads.objects[buffers[i]] = null;
        }
    },

    glDeleteFramebuffers(n, framebuffers) {
        quads.glDeleteBuffers(n, framebuffers);
    },

    glDeleteProgram(program) {
        quads.objects[program] = null;
    },

    glDeleteRenderbuffers(n, renderbuffers) {
        quads.glDeleteBuffers(n, renderbuffers);
    },

    glDeleteShader(shader) {
        quads.objects[shader] = null;
    },

    glDeleteTextures(n, textures) {
        quads.glDeleteBuffers(n, textures);
    },

    glDepthFunc(func) {
        quads.gl.depthFunc(func);
    },

    glDepthMask(flag) {
        quads.gl.depthMask(flag);
    },

    glDepthRangef(n, f) {
        quads.gl.depthRange(n, f);
    },

    glDetachShader(program, shader) {
        quads.gl.detachShader(quads.objects[program], quads.objects[shader]);
    },

    glDisable(cap) {
        quads.gl.disable(cap);
    },

    glDisableVertexAttribArray(index) {
        quads.gl.disableVertexAttribArray(index);
    },

    glDrawArrays(mode, first, count) {
        quads.gl.drawArrays(mode, first, count);
    },

    glDrawElements(mode, count, type, offset) {
        quads.gl.drawElements(mode, count, type, offset);
    },

    glDrawElementsInstanced(mode, count, type, indices, primcount) {
        quads.gl.drawElementsInstanced(mode, count, type, indices, primcount);
    },

    glEnable(cap) {
        quads.gl.enable(cap);
    },

    glEnableVertexAttribArray(index) {
        quads.gl.enableVertexAttribArray(index);
    },

    glVertexAttribDivisor(index, divisor) {
        quads.gl.vertexAttribDivisor(index, divisor);
    },

    glFinish() {
        quads.gl.finish();
    },

    glFlush() {
        quads.gl.flush();
    },

    glFramebufferRenderbuffer(target, attachment, renderbuffertarget, renderbuffer) {
        quads.gl.framebufferRenderbuffer(target, attachment, renderbuffertarget, quads.objects[renderbuffer]);
    },

    glFramebufferTexture2D(target, attachment, textarget, texture, level) {
        quads.gl.framebufferTexture2D(target, attachment, textarget, quads.objects[texture], level);
    },

    glFrontFace(mode) {
        quads.gl.frontFace(mode);
    },

    glGenBuffers(n, ptr) {
        const buffers = new Uint32Array(quads.module.exports.memory.buffer, ptr, n);
        for (let i = 0; i < n; i++) {
            buffers[i] = quads.pushObject(quads.gl.createBuffer());
        }
    },

    glGenVertexArrays(n, ptr) {
        const vaos = new Uint32Array(quads.module.exports.memory.buffer, ptr, n);
        for (let i = 0; i < n; i++) {
            vaos[i] = quads.pushObject(quads.gl.createVertexArray());
        }
    },

    glGenerateMipmap(target) {
        quads.gl.generateMipmap(target);
    },

    glGenFramebuffers(n, ptr) {
        const framebuffers = new Uint32Array(quads.module.exports.memory.buffer, ptr, n);
        for (let i = 0; i < n; i++) {
            framebuffers[i] = quads.pushObject(quads.gl.createFramebuffer());
        }
    },

    glGenRenderbuffers(n, ptr) {
        const renderbuffers = new Uint32Array(quads.module.exports.memory.buffer, ptr, n);
        for (let i = 0; i < n; i++) {
            renderbuffers[i] = quads.pushObject(quads.gl.createRenderbuffer());
        }
    },

    glGenTextures(n, ptr) {
        const textures = new Uint32Array(quads.module.exports.memory.buffer, ptr, n);
        for (let i = 0; i < n; i++) {
            textures[i] = quads.pushObject(quads.gl.createTexture());
        }
    },

    glGetActiveAttrib(program, index, bufSize, length, size, type, name) {
        const info = quads.gl.getActiveAttrib(quads.objects[program], index);
        if (info == null) return;
        new Int32Array(quads.module.exports.memory.buffer, size)[0] = info.size;
        new Uint32Array(quads.module.exports.memory.buffer, type)[0] = info.type;
        quads.setStringZ(name, bufSize, length, info.name);
    },

    glGetActiveUniform(program, index, bufSize, length, size, type, name) {
        const info = quads.gl.getActiveUniform(quads.objects[program], index);
        if (info == null) return;
        new Int32Array(quads.module.exports.memory.buffer, size)[0] = info.size;
        new Uint32Array(quads.module.exports.memory.buffer, type)[0] = info.type;
        quads.setStringZ(name, bufSize, length, info.name);
    },

    glGetAttachedShaders(program, maxCount, count, shaders) {
        const indices = quads.gl.getAttachedShaders(quads.objects[program]).map(shader => quads.objects.indexOf(shader));
        const buffer = new Uint32Array(quads.module.exports.memory.buffer, shaders);
        for (var i = 0; i < maxCount && i < indices.length; i++) {
            buffer[i] = indices[i];
        }
        if (count != 0) {
            new Int32Array(quads.module.exports.memory.buffer, count)[0] = i;
        }
    },

    glGetAttribLocation(program, name) {
        return quads.gl.getAttribLocation(quads.objects[program], quads.getStringZ(name));
    },

    glGetBooleanv(pname, params) {
        quads.setParams(Uint8Array, params, quads.gl.getParameter(pname));
    },

    glGetBufferParameteriv(target, value, data) {
        quads.setParams(Int32Array, data, quads.gl.getBufferParameter(target, value));
    },

    glGetError() {
        return quads.gl.getError();
    },

    glGetFloatv(pname, params) {
        quads.setParams(Float32Array, params, quads.gl.getParameter(pname));
    },

    glGetFramebufferAttachmentParameteriv(target, attachment, pname, params) {
        const value = quads.gl.getFramebufferAttachmentParameter(target, attachment, pname);
        if (typeof value == "object") {
            value = quads.objects.indexOf(value);
        }
        new Int32Array(quads.module.exports.memory.buffer, params)[0] = value;
    },

    glGetIntegerv(pname, params) {
        quads.setParams(Int32Array, params, quads.gl.getParameter(pname));
    },

    glGetProgramiv(program, pname, params) {
        quads.setParams(Int32Array, params, quads.gl.getProgramParameter(quads.objects[program], pname));
    },

    glGetProgramInfoLog(program, maxLength, length, infoLog) {
        quads.setStringZ(infoLog, maxLength, length, quads.gl.getProgramInfoLog(quads.objects[program]));
    },

    glGetRenderbufferParameteriv(target, pname, params) {
        quads.setParams(Int32Array, params, quads.gl.getRenderbufferParameter(target, pname));
    },

    glGetShaderiv(shader, pname, params) {
        quads.setParams(Int32Array, params, quads.gl.getShaderParameter(quads.objects[shader], pname));
    },

    glGetShaderInfoLog(shader, maxLength, length, infoLog) {
        quads.setStringZ(infoLog, maxLength, length, quads.gl.getShaderInfoLog(quads.objects[shader]));
    },

    glGetShaderPrecisionFormat(shaderType, precisionType, range, precision) {
        const format = quads.gl.getShaderPrecisionFormat(shaderType, precisionType);
        new Int32Array(quads.module.exports.memory.buffer, range, 2).set([format.rangeMin, format.rangeMax]);
        new Int32Array(quads.module.exports.memory.buffer, precision)[0] = format.precision;
    },

    glGetShaderSource(shader, bufSize, length, source) {
        quads.setStringZ(source, bufSize, length, quads.gl.getShaderSource(quads.objects[shader]));
    },

    glGetString() { },

    glGetTexParameterfv(target, pname, params) {
        quads.setParams(Float32Array, params, quads.gl.getTexParameter(target, pname));
    },

    glGetTexParameteriv(target, pname, params) {
        quads.setParams(Int32Array, params, quads.gl.getTexParameter(target, pname));
    },

    glGetUniformfv(program, location, params) {
        quads.setParams(Float32Array, params, quads.gl.getUniform(quads.objects[program], location));
    },

    glGetUniformiv(program, location, params) {
        quads.setParams(Int32Array, params, quads.gl.getUniform(quads.objects[program], location));
    },

    glGetUniformLocation(program, name) {
        const loc = quads.gl.getUniformLocation(quads.objects[program], quads.getStringZ(name));
        quads.uniforms[loc] = loc;
        return loc;
    },

    glGetVertexAttribfv(index, pname, params) {
        quads.setParams(Float32Array, params, quads.gl.getVertexAttrib(index, pname));
    },

    glGetVertexAttribiv(index, pname, params) {
        quads.setParams(Int32Array, params, quads.gl.getVertexAttrib(index, pname));
    },

    glGetVertexAttribPointerv(index, pname, pointer) {
        new Uint32Array(quads.module.exports.memory.buffer, pointer)[0] = quads.gl.getVertexAttribOffset(index, pname);
    },

    glHint(target, mode) {
        quads.gl.hint(target, mode);
    },

    glIsBuffer(buffer) {
        return quads.gl.isBuffer(quads.objects[buffer]);
    },

    glIsEnabled(cap) {
        return quads.gl.isEnabled(cap);
    },

    glIsFramebuffer(framebuffer) {
        return quads.gl.isFramebuffer(quads.objects[framebuffer]);
    },

    glIsProgram(program) {
        return quads.gl.isProgram(quads.objects[program]);
    },

    glIsRenderbuffer(renderbuffer) {
        return quads.gl.isRenderbuffer(quads.objects[renderbuffer]);
    },

    glIsShader(shader) {
        return quads.gl.isShader(quads.objects[shader]);
    },

    glIsTexture(texture) {
        return quads.gl.isTexture(quads.objects[texture]);
    },

    glLineWidth(width) {
        quads.gl.lineWidth(width);
    },

    glLinkProgram(program) {
        quads.gl.linkProgram(quads.objects[program]);
    },

    glPixelStorei(pname, param) {
        quads.gl.pixelStorei(pname, param);
    },

    glPolygonOffset(factor, units) {
        quads.gl.polygonOffset(factor, units);
    },

    glReadPixels(x, y, width, height, format, type, pixels) {
        quads.gl.readPixels(x, y, width, height, format, type, new Uint8Array(quads.module.exports.memory.buffer, pixels));
    },

    glRenderbufferStorage(target, internalformat, width, height) {
        quads.gl.renderbufferStorage(target, internalformat, width, height);
    },

    glSampleCoverage(value, invert) {
        quads.gl.sampleCoverage(value, invert);
    },

    glScissor(x, y, width, height) {
        quads.gl.scissor(x, y, width, height);
    },

    glShaderSource(shader, count, strings_ptr, lengths_ptr) {
        const strings = new Uint32Array(quads.module.exports.memory.buffer, strings_ptr, count);
        const lengths = new Int32Array(quads.module.exports.memory.buffer, lengths_ptr, count);
        var string = "";
        for (let i = 0; i < count; i++) {
            string += (lengths_ptr != 0 && lengths[i] >= 0) ? quads.getString(strings[i], lengths[i]) : quads.getStringZ(strings[i]);
        }
        quads.gl.shaderSource(quads.objects[shader], string);
    },

    glStencilFunc(func, ref, mask) {
        quads.gl.stencilFunc(func, ref, mask);
    },

    glStencilFuncSeparate(face, func, ref, mask) {
        quads.gl.stencilFuncSeparate(face, func, ref, mask);
    },

    glStencilMask(mask) {
        quads.gl.stencilMask(mask);
    },

    glStencilMaskSeparate(face, mask) {
        quads.gl.stencilMaskSeparate(face, mask);
    },

    glStencilOp(fail, zfail, zpass) {
        quads.gl.stencilOp(fail, zfail, zpass);
    },

    glStencilOpSeparate(face, sfail, dpfail, dppass) {
        quads.gl.stencilOpSeparate(face, sfail, dpfail, dppass);
    },

    glTexImage2D(target, level, internalformat, width, height, border, format, type, pixels) {
        quads.gl.texImage2D(target, level, internalformat, width, height, border, format, type, new Uint8Array(quads.module.exports.memory.buffer, pixels));
    },

    glTexParameterf(target, pname, param) {
        quads.gl.texParameterf(target, pname, param);
    },

    glTexParameteri(target, pname, param) {
        quads.gl.texParameteri(target, pname, param);
    },

    glTexSubImage2D(target, level, xoffset, yoffset, width, height, format, type, pixels) {
        quads.gl.texSubImage2D(target, level, xoffset, yoffset, width, height, format, type, new Uint8Array(quads.module.exports.memory.buffer, pixels));
    },

    glUniform1f(location, v0) {
        quads.gl.uniform1f(quads.uniforms[location], v0);
    },

    glUniform1fv(location, count, value) {
        quads.gl.uniform1fv(quads.uniforms[location], new Float32Array(quads.module.exports.memory.buffer, value, count));
    },

    glUniform1i(location, v0) {
        quads.gl.uniform1i(quads.uniforms[location], v0);
    },

    glUniform1iv(location, count, value) {
        quads.gl.uniform1iv(quads.uniforms[location], new Int32Array(quads.module.exports.memory.buffer, value, count));
    },

    glUniform2f(location, v0, v1) {
        quads.gl.uniform2f(quads.uniforms[location], v0, v1);
    },

    glUniform2fv(location, count, value) {
        quads.gl.uniform2fv(quads.uniforms[location], new Float32Array(quads.module.exports.memory.buffer, value, count));
    },

    glUniform2i(location, v0, v1) {
        quads.gl.uniform2i(quads.uniforms[location], v0, v1);
    },

    glUniform2iv(location, count, value) {
        quads.gl.uniform2iv(quads.uniforms[location], new Int32Array(quads.module.exports.memory.buffer, value, count));
    },

    glUniform3f(location, v0, v1, v2) {
        quads.gl.uniform3f(quads.uniforms[location], v0, v1, v2);
    },

    glUniform3fv(location, count, value) {
        quads.gl.uniform3fv(quads.uniforms[location], new Float32Array(quads.module.exports.memory.buffer, value, count));
    },

    glUniform3i(location, v0, v1, v2) {
        quads.gl.uniformif(quads.uniforms[location], v0, v1, v2);
    },

    glUniform3iv(location, count, value) {
        quads.gl.uniform3iv(quads.uniforms[location], new Int32Array(quads.module.exports.memory.buffer, value, count));
    },

    glUniform4f(location, v0, v1, v2, v3) {
        quads.gl.uniform4f(quads.uniforms[location], v0, v1, v2, v3);
    },

    glUniform4fv(location, count, value) {
        quads.gl.uniform4fv(quads.uniforms[location], new Float32Array(quads.module.exports.memory.buffer, value, count));
    },

    glUniform4i(location, v0, v1, v2, v3) {
        quads.gl.uniform4i(quads.uniforms[location], v0, v1, v2, v3);
    },

    glUniform4iv(location, count, value) {
        quads.gl.uniform4iv(quads.uniforms[location], new Int32Array(quads.module.exports.memory.buffer, value, count));
    },

    glUniformMatrix2fv(location, count, transpose, value) {
        quads.gl.uniformMatrix2fv(quads.uniforms[location], transpose, new Float32Array(quads.module.exports.memory.buffer, value, count));
    },

    glUniformMatrix3fv(location, count, transpose, value) {
        quads.gl.uniformMatrix3fv(quads.uniforms[location], transpose, new Float32Array(quads.module.exports.memory.buffer, value, count));
    },

    glUniformMatrix4fv(location, count, transpose, value) {
        quads.gl.uniformMatrix4fv(quads.uniforms[location], transpose, new Float32Array(quads.module.exports.memory.buffer, value, count));
    },

    glUseProgram(program) {
        quads.gl.useProgram(quads.objects[program]);
    },

    glValidateProgram(program) {
        quads.gl.validateProgram(quads.objects[program]);
    },

    glVertexAttrib1f(index, x) {
        quads.gl.vertexAttrib1f(index, x);
    },

    glVertexAttrib1fv(index, v) {
        quads.gl.vertexAttrib1fv(index, new Float32Array(quads.module.exports.memory.buffer, v));
    },

    glVertexAttrib2f(index, x, y) {
        quads.gl.vertexAttrib2f(index, x, y);
    },

    glVertexAttrib2fv(index, v) {
        quads.gl.vertexAttrib2fv(index, new Float32Array(quads.module.exports.memory.buffer, v));
    },

    glVertexAttrib3f(index, x, y, z) {
        quads.gl.vertexAttrib3f(index, x, y, z);
    },

    glVertexAttrib3fv(index, v) {
        quads.gl.vertexAttrib3fv(index, new Float32Array(quads.module.exports.memory.buffer, v));
    },

    glVertexAttrib4f(index, x, y, z, w) {
        quads.gl.vertexAttrib4f(index, x, y, z, w);
    },

    glVertexAttrib4fv(index, v) {
        quads.gl.vertexAttrib4fv(index, new Float32Array(quads.module.exports.memory.buffer, v));
    },

    glVertexAttribPointer(index, size, type, normalized, stride, offset) {
        quads.gl.vertexAttribPointer(index, size, type, normalized, stride, offset);
    },

    glViewport(x, y, width, height) {
        quads.gl.viewport(x, y, width, height);
    },

    keys: {
        KeyA: 5,
        KeyB: 6,
        KeyC: 7,
        KeyD: 8,
        KeyE: 9,
        KeyF: 10,
        KeyG: 11,
        KeyH: 12,
        KeyI: 13,
        KeyJ: 14,
        KeyK: 15,
        KeyL: 16,
        KeyM: 17,
        KeyN: 18,
        KeyO: 19,
        KeyP: 20,
        KeyQ: 21,
        KeyR: 22,
        KeyS: 23,
        KeyT: 24,
        KeyU: 25,
        KeyV: 26,
        KeyW: 27,
        KeyX: 28,
        KeyY: 29,
        KeyZ: 30,
        Digit1: 31,
        Digit2: 32,
        Digit3: 33,
        Digit4: 34,
        Digit5: 35,
        Digit6: 36,
        Digit7: 37,
        Digit8: 38,
        Digit9: 39,
        Digit0: 40,
        Enter: 41,
        Escape: 42,
        Backspace: 43,
        Tab: 44,
        Space: 45,
        Minus: 46,
        Equal: 47,
        BracketLeft: 48,
        BracketRight: 49,
        Backslash: 50,
        Semicolon: 51,
        Quote: 52,
        Backquote: 53,
        Comma: 54,
        Period: 55,
        Slash: 56,
        CapsLock: 57,
        F1: 58,
        F2: 59,
        F3: 60,
        F4: 61,
        F5: 62,
        F6: 63,
        F7: 64,
        F8: 65,
        F9: 66,
        F10: 67,
        F11: 68,
        F12: 69,
        PrintScreen: 70,
        ScrollLock: 71,
        Pause: 72,
        Insert: 73,
        Home: 74,
        PageUp: 75,
        Delete: 76,
        End: 77,
        PageDown: 78,
        ArrowRight: 79,
        ArrowLeft: 80,
        ArrowDown: 81,
        ArrowUp: 82,
        NumLock: 83,
        NumpadDivide: 84,
        NumpadMultiply: 85,
        NumpadSubtract: 86,
        NumpadAdd: 87,
        NumpadEnter: 88,
        Numpad1: 89,
        Numpad2: 90,
        Numpad3: 91,
        Numpad4: 92,
        Numpad5: 93,
        Numpad6: 94,
        Numpad7: 95,
        Numpad8: 96,
        Numpad9: 97,
        Numpad0: 98,
        NumpadDecimal: 99,
        IntlBackslash: 100,
        ContextMenu: 101,
        NumpadEqual: 102,
        F13: 103,
        F14: 104,
        F15: 105,
        F16: 106,
        F17: 107,
        F18: 108,
        F19: 109,
        F20: 110,
        F21: 111,
        F22: 112,
        F23: 113,
        F24: 114,
        NumpadComma: 115,
        IntlRo: 116,
        KanaMode: 117,
        IntlYen: 118,
        Convert: 119,
        NonConvert: 120,
        Lang1: 121,
        Lang2: 122,
        ControlLeft: 123,
        ShiftLeft: 124,
        AltLeft: 125,
        MetaLeft: 126,
        ControlRight: 127,
        ShiftRight: 128,
        AltRight: 129,
        MetaRight: 130,
    },

    buttons: {
        0: 0,
        1: 2,
        2: 1,
        3: 3,
        4: 4,
    },
};