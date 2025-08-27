package game

import "base:runtime"
import "base:intrinsics"
import "core:fmt"
import "core:time"
import "core:math"
import "core:c"
import "core:os"
import "core:c/libc"
import "core:strings"

/*
   This is not from handmade hero,
   Its based on: https://blog.demofox.org/diy-synthesizer/
   in order to familiarize myself with audio programming.

   Wave files are pretty much this: http://soundfile.sapp.org/doc/WaveFormat/

   Why you shouldn't do floating point audio: https://losslessbits.com/floating-point/
 */

wav_test :: proc() {
  // 44100 samples means 22050 frames, with sample_rate = 44100 means half a second wav
  data : [44100]i16
  for sample_idx in 0..<22050{
      freq := 440
      phase := f32(sample_idx*freq) / f32(22050)
      volume :: 0.3
      sample := math.sin(phase*2*math.PI) * volume
      data[2*sample_idx] = i16(f32(max(i16))*sample)
      data[2*sample_idx+1] = i16(f32(max(i16))*sample)
  }
  wav_write(2, 44100, data[:], "sample.wav")
}

Wave_File_Header :: struct {
// RIFF header
  chunk_id : [4]u8, // must contain RIFF for some reason
  chunk_size : u32, // 4 + (8 + SubChunk1Size) + (8 + SubChunk2Size)
  format : [4]u8,   // must contain WAVE
// fmt subchunk (also called subchunk1)
  subchunk1_id : [4]u8, // must contain "fmt "
  subchunk1_size : u32, // size of rest of subchunk that follows this number
  audio_format : u16, // must be 1 because PCM=1 and we do PCM, 0 is too little, 2 is too much, OK?
  num_channels : u16, // MONO=1, STEREO=2 etc..
  sample_rate : u16, // samples per second e.g 44100,44100,444100,etc..
  byte_rate : u32, // sample_rate * num_channels * (bits_per_sample/8), frame bytes per second
  block_align : u16, // num_channels * (bits_per_sample/8), bytes per frame (multitude of samples)
  bits_per_sample : u16, // bits per sample :|
// data subchunk (also called subchunk2)
  subchunk2_id : [4]u8, // must contain "data"
  subchunk2_size : u32, // size of rest of subchunk that follows this number

  // After this we got raw data..
  // data : []u8
};

// TODO: a direct write works because we run this on little endian hardware, we should probably handle big endian devices too
// TODO: make the data field HAVE to be numeric
wav_write :: proc(num_channels : u16, sample_rate : u16, raw_data : []$T, dest_path : string) -> (ok : bool){
  wfh : Wave_File_Header

  DATA_SIZE := u32(len(raw_data) + size_of(raw_data))

  // RIFF HEADER
  riff := "RIFF"
  intrinsics.mem_copy(&wfh.chunk_id[0], &(transmute([]u8)riff)[0], 4)
  wfh.chunk_size = DATA_SIZE + 36
  wave := "WAVE"
  intrinsics.mem_copy(&wfh.format[0], &(transmute([]u8)wave)[0], 4)

  // fmt subchunk
  fmt := "fmt "
  intrinsics.mem_copy(&wfh.subchunk1_id[0], &(transmute([]u8)fmt)[0], 4)
  wfh.subchunk1_size = 16
  wfh.audio_format = 1
  wfh.num_channels = num_channels
  wfh.sample_rate = sample_rate
  wfh.bits_per_sample = size_of(raw_data[0]) * 8
  wfh.byte_rate = u32(wfh.sample_rate * wfh.num_channels * wfh.bits_per_sample/8)
  wfh.block_align = u16(wfh.num_channels * wfh.bits_per_sample/8)

  // data subchunk
  data := "data"
  intrinsics.mem_copy(&wfh.subchunk2_id[0], &(transmute([]u8)data)[0], 4)
  wfh.subchunk2_size = DATA_SIZE


  file := libc.fopen(strings.clone_to_cstring(dest_path), "w+b");
  libc.fwrite(&wfh, size_of(Wave_File_Header), 1, file);
  libc.fwrite(&raw_data[0], len(raw_data) * size_of(raw_data[0]), 1, file);
  libc.fclose(file)

  return true
}
