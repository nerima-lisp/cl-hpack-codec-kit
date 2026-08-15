(in-package #:hpack-codec/test)

(describe "hpack-huffman-encode"
  ;; RFC 7541 C.4.1: the :authority value of the first request example.
  (it "matches the RFC 7541 encoding of www.example.com"
    (expect (hpack-huffman-encode (ascii "www.example.com"))
            :to-equalp
            (octets #xf1 #xe3 #xc2 #xe5 #xf2 #x3a #x6b #xa0 #xab #x90 #xf4 #xff)))

  ;; RFC 7541 C.4.2: the cache-control value of the second request example.
  (it "matches the RFC 7541 encoding of no-cache"
    (expect (hpack-huffman-encode (ascii "no-cache"))
            :to-equalp
            (octets #xa8 #xeb #x10 #x64 #x9c #xbf)))

  (it "encodes the empty input as the empty output"
    (expect (hpack-huffman-encode (ascii "")) :to-equalp (octets))))

(describe "hpack-huffman-decode"
  (it "recovers the RFC 7541 encoding of www.example.com"
    (expect (hpack-huffman-decode
             (octets #xf1 #xe3 #xc2 #xe5 #xf2 #x3a #x6b #xa0 #xab #x90 #xf4 #xff))
            :to-equalp
            (ascii "www.example.com")))

  (it "recovers the RFC 7541 encoding of no-cache"
    (expect (hpack-huffman-decode (octets #xa8 #xeb #x10 #x64 #x9c #xbf))
            :to-equalp
            (ascii "no-cache")))

  ;; A run of zero bits never completes a code and never matches the all-ones
  ;; padding rule, so it must be rejected rather than silently truncated.
  (it "rejects padding that is not a prefix of the EOS code"
    (signals hpack-codec-error (hpack-huffman-decode (octets #x00))))

  ;; Eight all-ones bits leave a full byte of padding, which exceeds the seven
  ;; bits RFC 7541 permits.
  (it "rejects padding longer than seven bits"
    (signals hpack-codec-error
      (hpack-huffman-decode
       (octets #xf1 #xe3 #xc2 #xe5 #xf2 #x3a #x6b #xa0 #xab #x90 #xf4 #xff #xff)))))

(describe "huffman round trip"
  ;; Regression: symbol 9 was carried as #xfffea, four bits short of its
  ;; declared 24-bit width, so a field value containing a tab encoded into a
  ;; stream no decoder could read back. It is the only symbol whose code is
  ;; shorter than its neighbours', which is what let the typo survive.
  (it "round trips a tab, whose code is a bit-width special case"
    (let ((input (octets 9)))
      (expect (hpack-huffman-decode (hpack-huffman-encode input))
              :to-equalp input)))

  (it "recovers every printable ASCII octet"
    (let ((input (map '(vector (unsigned-byte 8)) #'identity
                      (loop for code from 32 below 127 collect code))))
      (expect (hpack-huffman-decode (hpack-huffman-encode input))
              :to-equalp input)))

  (it "recovers every octet value"
    (let ((input (map '(vector (unsigned-byte 8)) #'identity
                      (loop for code below 256 collect code))))
      (expect (hpack-huffman-decode (hpack-huffman-encode input))
              :to-equalp input))))
