(in-package #:hpack-codec/test)

(describe "hpack-encode-integer"
  ;; RFC 7541 C.1.1: 10 fits below the 5-bit prefix mask, so it occupies the
  ;; prefix alone.
  (it "encodes a value below the prefix mask in one octet"
    (expect (hpack-encode-integer 10 5 0) :to-equalp (octets 10)))

  ;; RFC 7541 C.1.2: 1337 overflows the prefix and continues over two more
  ;; octets, the last without the continuation bit.
  (it "encodes a value above the prefix mask with continuation octets"
    (expect (hpack-encode-integer 1337 5 0) :to-equalp (octets #x1f #x9a #x0a)))

  ;; RFC 7541 C.1.3: an 8-bit prefix starts on an octet boundary.
  (it "encodes with a full eight-bit prefix"
    (expect (hpack-encode-integer 42 8 0) :to-equalp (octets 42)))

  (it "keeps the flag bits supplied by the prefix"
    (expect (hpack-encode-integer 2 6 #x80) :to-equalp (octets #x82)))

  (it "rejects a negative value"
    (signals hpack-codec-error (hpack-encode-integer -1 5 0)))

  (it "rejects a prefix width outside one to eight bits"
    (signals hpack-codec-error (hpack-encode-integer 1 0 0))
    (signals hpack-codec-error (hpack-encode-integer 1 9 0))))

(describe "hpack-read-integer"
  (it "reads a value stored entirely in the prefix"
    (multiple-value-bind (value position)
        (hpack-read-integer (octets 10) 0 5)
      (expect value :to-equalp 10)
      (expect position :to-equalp 1)))

  (it "reads a value spread over continuation octets"
    (multiple-value-bind (value position)
        (hpack-read-integer (octets #x1f #x9a #x0a) 0 5)
      (expect value :to-equalp 1337)
      (expect position :to-equalp 3)))

  (it "ignores the flag bits above the prefix"
    (multiple-value-bind (value position)
        (hpack-read-integer (octets #x82) 0 6)
      (expect value :to-equalp 2)
      (expect position :to-equalp 1)))

  (it "rejects reading past the end of the input"
    (signals hpack-codec-error (hpack-read-integer (octets) 0 5))
    (signals hpack-codec-error (hpack-read-integer (octets 10) 1 5)))

  (it "rejects a truncated continuation"
    (signals hpack-codec-error (hpack-read-integer (octets #x1f #x9a) 0 5)))

  (it "rejects an integer wider than thirty-two bits"
    (signals hpack-codec-error
      (hpack-read-integer (octets #x1f #xff #xff #xff #xff #xff #xff) 0 5))))

(describe "prefixed integer round trip"
  (it "recovers every value it encodes across each prefix width"
    (loop for prefix-bits from 1 to 8
          do (dolist (value '(0 1 30 31 32 127 128 1337 65535 16777216))
               (multiple-value-bind (decoded position)
                   (hpack-read-integer
                    (hpack-encode-integer value prefix-bits 0)
                    0
                    prefix-bits)
                 (expect decoded :to-equalp value)
                 (expect (plusp position)))))))
