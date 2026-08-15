# cl-hpack-codec-kit

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

cl-hpack-codec-kit is the pair of primitive codecs RFC 7541 defines and RFC
9204 reuses: the canonical Huffman code for header strings, and the prefixed
integer representation. It has no dependencies and knows nothing about HTTP
messages, header tables, or connections.

It exists because HPACK and QPACK share these two codecs but nothing else.
HTTP/2's dynamic table and HTTP/3's are different designs, but both encode
their lengths and indices as prefixed integers and both compress strings with
the same Huffman table, so the codec belongs to neither and is depended on by
both.

## Install

```lisp
(asdf:load-system "cl-hpack-codec-kit")
```

## Usage

Both codecs work on octet vectors and return fresh octet vectors.

```lisp
(hpack-codec:hpack-huffman-encode
 (map '(vector (unsigned-byte 8)) #'char-code "www.example.com"))
;; => #(241 227 194 229 242 58 107 160 171 144 244 255)

(hpack-codec:hpack-huffman-decode
 #(241 227 194 229 242 58 107 160 171 144 244 255))
;; => #(119 119 119 46 101 120 97 109 112 108 101 46 99 111 109)
```

A prefixed integer carries its low bits in the first octet alongside caller
supplied flag bits, continuing over further octets when the value does not
fit. `hpack-encode-integer` takes the value, the prefix width, and the flag
bits; `hpack-read-integer` returns the value and the position just past it.

```lisp
(hpack-codec:hpack-encode-integer 1337 5 0)   ; => #(31 154 10)
(hpack-codec:hpack-read-integer #(31 154 10) 0 5)
;; => 1337, 3
```

## API

| Operation | Purpose |
| --- | --- |
| `hpack-huffman-encode` | Encode octets with the RFC 7541 Appendix B Huffman table |
| `hpack-huffman-decode` | Decode Huffman octets, rejecting EOS and malformed padding |
| `hpack-encode-integer` | Encode a prefixed integer with the given prefix width and flags |
| `hpack-read-integer` | Decode a prefixed integer, returning the value and next position |
| `hpack-codec-error` | Condition signalled for malformed input, with `message`, `operation` and `detail` readers |

`hpack-codec-error` carries the same three slots as the protocol-error
conditions in the HTTP libraries that consume this kit, so a caller can
translate one into the other without losing the diagnostic payload.

## Conformance

The Huffman codec is checked against the worked examples in RFC 7541 Appendix
C — C.4.1 (`www.example.com`) and C.4.2 (`no-cache`) — and against a round
trip over all 256 octet values. The integer codec is checked against C.1.1,
C.1.2 and C.1.3, and round trips every prefix width from one to eight bits.

Decoding rejects an unknown code, an embedded EOS symbol, padding longer than
seven bits, and padding that is not a prefix of the EOS code. The integer
decoder rejects truncated input and values wider than 32 bits.

## License

MIT. See [LICENSE](LICENSE).
