package handmade

import "base:intrinsics"
import "base:runtime"
import "core:flags"
import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
import "core:mem"
import win "core:sys/windows"
import "vendor:windows/GameInput"
import xaudio2 "vendor:windows/XAudio2"


win32_init_xaudio :: proc() {
	result := win.CoInitializeEx(nil, win.COINIT.MULTITHREADED)
	if win.FAILED(result) {
		fmt.println("error initializing com")
		return
	}
	defer win.CoInitialize()

	x2_object: ^xaudio2.IXAudio2
	result = xaudio2.Create(&x2_object, nil, xaudio2.USE_DEFAULT_PROCESSOR)
	if win.FAILED(result) {
		fmt.println("failed to create xaudio engine")
		return
	}

	master_voice: ^xaudio2.IXAudio2MasteringVoice
	result = x2_object.CreateMasteringVoice(
		x2_object,
		&master_voice,
		xaudio2.DEFAULT_CHANNELS,
		xaudio2.DEFAULT_SAMPLERATE,
		nil,
		nil,
		nil,
		.Other,
	)
	if win.FAILED(result) {
		fmt.println("failed to create mastering voice")
		return
	}

	fmt.println("xaudio initialized successfully")

	global_wfx = {
		wFormatTag      = win.WAVE_FORMAT_PCM,
		nChannels       = 2,
		nSamplesPerSec  = 44100,
		nAvgBytesPerSec = 44100 * 2 * 2,
		nBlockAlign     = 2 * 2,
		wBitsPerSample  = 16,
		cbSize          = 0,
	}


	result = x2_object.CreateSourceVoice(
		x2_object,
		&global_source_voice,
		&global_wfx,
		nil,
		xaudio2.DEFAULT_FREQ_RATIO,
		nil,
		nil,
		nil,
	)
	if win.FAILED(result) {
		fmt.println("failed to create soource voice")
	}

	sample_rate :: 44100
	duration :: 1.0
	total_samples :: sample_rate * duration
	frequency :: 390.0

	raw_pcm_data := make([]u8, int(total_samples))

	for i in 0 ..< int(total_samples) {
		t := f64(i) / f64(sample_rate)
		sample_val := math.sin(2.0 * math.PI * frequency * t)
		raw_pcm_data[i] = u8(sample_val * 32767.0)
	}

	audio_buffer: xaudio2.BUFFER = {
		Flags      = {.END_OF_STREAM},
		AudioBytes = u32(len(raw_pcm_data)),
		pAudioData = raw_data(raw_pcm_data),
	}

	result = global_source_voice.SubmitSourceBuffer(global_source_voice, &audio_buffer, nil)
	if win.FAILED(result) {
		fmt.println("failed to submit source buffer")
		return
	}

	result = global_source_voice.Start(global_source_voice, nil, 0)
	if win.FAILED(result) {
		fmt.println("failed to start playback")
		return
	}
}
