# cl-hpack-codec-kit

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

`cl-hpack-codec-kit` is a dependency-free Common Lisp implementation of the
HPACK header compression format specified by [RFC 7541](https://www.rfc-editor.org/rfc/rfc7541.html).
It provides the static table, per-context dynamic tables, all four header-field
representations, RFC Huffman strings, prefixed integers, stateful header-block
encoders and decoders, protocol error conditions, and resource limits.

## Install

```lisp
(asdf:load-system "cl-hpack-codec-kit")
```

The test system is available as `cl-hpack-codec-kit/test` and uses `cl-weave`
only for the test runner.

## Encode and decode a header block

Headers may be supplied as string pairs, dotted pairs, three-element lists
with an explicit representation, vectors, or `hpack-header` objects. Strings
are converted to octets; octet vectors are accepted for arbitrary field bytes.

```lisp
(let* ((encoder (hpack-codec:make-hpack-encoder :huffman :auto))
       (decoder (hpack-codec:make-hpack-decoder))
       (block
         (hpack-codec:hpack-encode-header-block
          encoder
          '((":method" . "GET")
            (":path" . "/")
            (":authority" . "www.example.com"))))
       (headers (hpack-codec:hpack-decode-header-block decoder block)))
  headers)
```

The encoder and decoder retain their own dynamic-table state between blocks.
Use `hpack-encoder-set-table-size` and `hpack-decoder-set-table-size` when the
peer's table-size setting changes. The encoder emits the required leading
table-size updates, including the two-update sequence required when both an
intermediate minimum and a final size must be signaled.

For transports that deliver a header block in fragments, use
`hpack-decoder-feed` for each octet vector and `hpack-decoder-finish` when the
block boundary is known. The dynamic table is committed only by a successful
`finish`; malformed or incomplete input remains buffered for another fragment,
and `hpack-decoder-abort` discards it.

## Header representations

`make-hpack-header` accepts `:representation` values of `:auto`, `:indexed`,
`:incremental-indexing`, `:without-indexing`, and `:never-indexed`.

```lisp
(hpack-codec:make-hpack-header
 :name "authorization"
 :value "opaque-value"
 :representation :never-indexed)
```

`:auto` uses an indexed representation for an exact table match and incremental
indexing for a new field. The explicit modes let callers control indexing for
sensitive or non-reusable values. Decoding preserves the representation on each
returned `hpack-header`.

## Limits and errors

Both constructors accept limits for block bytes, header-list bytes, field
count, string length, and dynamic-table size:

```lisp
(hpack-codec:make-hpack-decoder
 :maximum-table-size 4096
 :maximum-block-size (* 4 1024 1024)
 :maximum-header-list-size (* 8 1024 1024)
 :maximum-field-count 4096
 :maximum-string-length (* 1024 1024))
```

Malformed HPACK input signals `hpack-decoding-error`. A validly formed input
that exceeds a configured resource bound signals `hpack-limit-error`; both are
subtypes of `hpack-codec-error` and expose message, operation, and detail
readers. Decoder table changes are committed only after a complete block has
decoded successfully, so a failed block does not partially update dynamic
state.

## Primitive codecs

The lower-level APIs operate on octet vectors and return fresh octet vectors.

```lisp
(hpack-codec:hpack-huffman-encode octets)
(hpack-codec:hpack-huffman-decode encoded-octets)
(hpack-codec:hpack-encode-integer 1337 5 0)
(hpack-codec:hpack-read-integer #(31 154 10) 0 5)
(hpack-codec:hpack-encode-string octets :huffman :auto)
(hpack-codec:hpack-read-string encoded-octets 0)
```

The Huffman codec rejects EOS symbols and malformed padding. The integer codec
validates prefix widths and truncation, enforcing a 32-bit maximum by default;
callers can provide a larger explicit maximum for standalone integer coding.

## Conformance

The test suite covers the RFC 7541 static table and request examples, including
the exact Appendix C.3 and C.4 byte sequences; all four field representations;
dynamic-table insertion, lookup, eviction, and size updates; raw and Huffman
strings; arbitrary octets; malformed indices, truncation, illegal updates, and
transactional rollback; and encoder/decoder resource limits.

## License

MIT. See [LICENSE](LICENSE).
