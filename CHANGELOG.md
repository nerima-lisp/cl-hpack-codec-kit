# Changelog

## [1.1.2]

### Tests

- Added regression coverage for custom Huffman-table prefix collisions and
  duplicate codes, EOS rejection, invalid integer input, and maximum-value
  boundaries.
- Runtime code, public API, and wire behavior are unchanged.

## [1.1.1]

### Fixed

- Added a Nix check that runs the ASDF test suite. The green v1.1.0 CI runs did
  not execute tests because the flake had no `checks` output.
- Applied per-call decoder header-list limits before copying raw strings, added
  call-specific options to fragmented decoding, and kept configured header-name
  validation enabled for every call.
- Added configurable resource limits to static-only encoding and removed
  duplicate representation checks.

### Documentation

- Restored the MIT license badge and the decoder's successful-block commit
  guarantee. Clarified that pseudo-header protocol semantics belong to the
  HTTP/2 layer using the codec.

## [1.1.0]

### Added

- Stateless static-table header-block encoding and a per-call sensitive-field
  predicate for stateful and static-only encoding.
- Per-call decoder limits, opt-in HTTP/2 header-name validation, and the public
  `hpack-valid-header-name-p` predicate.

### Documentation

- Expanded the public API guide for static-only encoding, per-call decoding
  limits, header-name validation, and the decoder table-size setting.

## [1.0.0]

### Added

- RFC 7541 Huffman codec (`hpack-huffman-encode`, `hpack-huffman-decode`).
- RFC 7541 prefixed-integer codec (`hpack-encode-integer`, `hpack-read-integer`).
- HPACK string literal codec (`hpack-encode-string`, `hpack-read-string`),
  selecting raw or Huffman payload encoding.
- The RFC 7541 static table and a per-context dynamic table, including
  insertion, eviction, exact and name-only lookup, and size updates.
- Stateful header-block encoder and decoder (`make-hpack-encoder`,
  `make-hpack-decoder`, `hpack-encode-header-block`,
  `hpack-decode-header-block`) supporting all four field representations
  (`:indexed`, `:incremental-indexing`, `:without-indexing`,
  `:never-indexed`) and `:auto` selection.
- Fragmented decoding (`hpack-decoder-feed`, `hpack-decoder-finish`,
  `hpack-decoder-abort`), with dynamic-table commits gated on a
  successfully decoded block.
- `hpack-codec-error`, `hpack-decoding-error`, and `hpack-limit-error`
  conditions, and configurable resource limits for block size, header-list
  size, field count, string length, and table size.
