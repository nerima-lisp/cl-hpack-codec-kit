# cl-hpack-codec-kit

`cl-hpack-codec-kit` is a dependency-free Common Lisp implementation of the
HPACK header compression format specified by [RFC 7541](https://www.rfc-editor.org/rfc/rfc7541.html).
It provides the static table, per-context dynamic tables, all four header-field
representations, RFC Huffman strings, prefixed integers, stateful header-block
encoders and decoders, protocol error conditions, and resource limits.

## Install

With SBCL installed, clone the repository and run the following from its root.
`CL_SOURCE_REGISTRY` adds the checkout to ASDF's source registry for this
command.

```sh
git clone https://github.com/nerima-lisp/cl-hpack-codec-kit.git
cd cl-hpack-codec-kit
CL_SOURCE_REGISTRY="$PWD//" sbcl --non-interactive \
  --eval '(require :asdf)' \
  --eval '(asdf:load-system "cl-hpack-codec-kit")'
```

The library loads through ASDF without Nix. The test system is available as
`cl-hpack-codec-kit/test` and uses `cl-weave` only for the test runner; see
Conformance for test commands.

## Encode and decode a header block

Pass the header sequence as a list or vector. Each header may be a two-element
list, a dotted pair, a three-element list with an explicit representation, or
an `hpack-header` object. A three-element list has the form
`(name value representation)`. Strings are converted to octets; octet vectors
are accepted for arbitrary field bytes. Each string character's code point becomes
one octet; characters above `#xFF` are rejected.

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
**Encoder side:** when the peer sends `SETTINGS_HEADER_TABLE_SIZE`, pass that
value to your `hpack-encoder-set-table-size`; it limits your outbound encoder's
table and queues an update for the next block. **Decoder side:** when you send
`SETTINGS_HEADER_TABLE_SIZE` to the peer, pass that advertised value to your
`hpack-decoder-set-table-size`; it limits the inbound encoder's table, lowers
your current table if necessary, and rejects later peer updates above that
ceiling. If several encoder size changes arrive before the next block, the
encoder emits the lowest size reached, followed by the final size. For example,
lowering to 256 and then raising to 512 emits updates for 256 and 512.

For fragmented input, call `hpack-decoder-feed` for each chunk in order. Call
`hpack-decoder-finish` once, after outer framing marks the complete block; do not
call it after every fragment, because a valid prefix could otherwise be treated
as a complete block. A successful finish clears the buffered bytes and commits
table changes. A failed finish leaves the fragments buffered. If framing shows
that more fragments belong to that same incomplete block, feed those fragments
to the same decoder, then call `hpack-decoder-finish` after framing marks the
complete boundary. If framing confirms that the block is complete, call
`hpack-decoder-abort` after the error before reading another block; the
condition does not distinguish a truncated block from malformed input.

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

## Static-only encoding and sensitive fields

`hpack-encode-static-header-block` encodes a block without an encoder or dynamic
table state. With `:auto` headers, exact matches in the RFC static table use an
indexed representation; other fields use non-indexing literals. Explicit
`:without-indexing` and `:never-indexed` representations are preserved, while
`:incremental-indexing` becomes a non-indexing literal.
An explicit `:indexed` representation requires an exact static-table match;
otherwise the encoder signals `hpack-codec-error`.

Both `hpack-encode-header-block` and `hpack-encode-static-header-block` accept a
`:sensitive-predicate`. The function receives each normalized name and value as
an octet vector. A true result forces the field to use `:never-indexed`, even
when it otherwise matches a table entry or has an explicit representation.

```lisp
(hpack-codec:hpack-encode-static-header-block
 '((":method" . "GET")
   ("authorization" . "Bearer example-token")
   ("x-trace-id" . "opaque-value"))
 :huffman :auto
 :sensitive-predicate
 (lambda (name value)
   (declare (ignore value))
   (equalp name
           (map '(vector (unsigned-byte 8)) #'char-code "authorization"))))
```

## HTTP/2 header names and per-call decode limits

Set `:validate-header-names t` on `make-hpack-decoder` to validate every decoded
field name, or pass `:validate-header-names` to one
`hpack-decode-header-block` call to override the decoder's setting for that
block. Validation is opt-in so generic HPACK users retain the existing
octet-level behavior.
`hpack-valid-header-name-p` exposes the same lowercase HTTP/2 token check for
application code; pseudo-header names may start with one colon.

```lisp
(hpack-codec:hpack-decode-header-block
 decoder block
 :max-fields 128
 :max-header-bytes (* 32 1024)
 :validate-header-names t)
```

`:max-fields` and `:max-header-bytes` apply only to that call. Header bytes use
the RFC header-list accounting rule of 32 bytes plus each name and value length.
The effective limit is the smaller of the per-call value and the decoder's
configured default, so a per-call value cannot relax the default or change it.
Those call options tighten `make-hpack-decoder`'s `:maximum-field-count` and
`:maximum-header-list-size` limits, respectively.

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

Both encoders and decoders enforce these limits unless constructor options
override them: a 4,096-byte dynamic table, a 16 MiB header block, a 16 MiB
header list, a 16 MiB string, and 65,536 fields per block.

Malformed HPACK input signals `hpack-decoding-error`. A validly formed input
that exceeds a configured resource bound signals `hpack-limit-error`; both are
subtypes of `hpack-codec-error` and expose message, operation, and detail
readers named `hpack-codec-error-message`, `hpack-codec-error-operation`, and
`hpack-codec-error-detail`.

## Primitive codecs

The lower-level APIs operate on octet vectors. Encoding functions return fresh
octet vectors; integer and string readers return decoded values and the next
position.

```lisp
(hpack-codec:hpack-huffman-encode octets)
(hpack-codec:hpack-huffman-decode encoded-octets)
(hpack-codec:hpack-encode-integer 1337 5 0)
(hpack-codec:hpack-encode-integer 1337 5 0 :maximum #x1ffffffff)
(hpack-codec:hpack-read-integer #(31 154 10) 0 5)
(hpack-codec:hpack-encode-string octets :huffman :auto)
(hpack-codec:hpack-read-string encoded-octets 0)
```

The Huffman codec rejects EOS symbols and malformed padding. The integer codec
validates prefix widths and truncation, enforcing a 32-bit maximum by default;
pass `:maximum` to `hpack-encode-integer` or `hpack-read-integer` to allow a
larger value for standalone integer coding.

## Conformance

Run the test system with `nix run .#test` or, when `cl-weave` is available to
ASDF, `(asdf:test-system "cl-hpack-codec-kit/test")`.

The test suite covers the RFC 7541 static table and request examples, including
the exact Appendix C.3 and C.4 byte sequences; all four field representations;
dynamic-table insertion, lookup, eviction, and size updates; raw and Huffman
strings; arbitrary octets; malformed indices, truncation, illegal updates, and
transactional rollback; and encoder/decoder resource limits.

## License

MIT. See [LICENSE](LICENSE).
