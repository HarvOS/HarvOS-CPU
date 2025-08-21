// SPDX-License-Identifier: MIT
package dcache_params_pkg;
  parameter integer LINE_BYTES    = 32;              // 32B line
  parameter integer WORD_BYTES    = 4;
  parameter integer WORDS_PER_LINE= LINE_BYTES/WORD_BYTES; // 8 words
  parameter integer SETS          = 64;             // example: 64 sets
  parameter integer IDX_BITS      = $clog2(SETS);
  parameter integer OFF_BITS      = $clog2(LINE_BYTES);
  parameter integer WORD_IDX_BITS = $clog2(WORDS_PER_LINE);
endpackage
