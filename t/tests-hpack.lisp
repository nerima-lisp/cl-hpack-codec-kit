(in-package #:hpack-codec/test)

(defun header-pairs (headers)
  (mapcar (lambda (header)
            (list (hpack-header-name header)
                  (hpack-header-value header)))
          headers))

(describe "HPACK static and dynamic tables"
  (it "exposes the RFC static table and protects its storage"
    (expect (hpack-static-table-count) :to-equalp 61)
    (let ((entry (hpack-static-table-entry 2)))
      (expect (hpack-table-entry-name entry) :to-equalp (ascii ":method"))
      (expect (hpack-table-entry-value entry) :to-equalp (ascii "GET"))
      (setf (aref (hpack-table-entry-name entry) 0) (char-code #\x)))
    (expect (hpack-table-entry-name (hpack-static-table-entry 2))
            :to-equalp
            (ascii ":method")))

  (it "inserts newest entries and evicts oldest entries by RFC size"
    (let ((table (make-hpack-table :maximum-size 64)))
      (hpack-table-insert table (ascii "a") (ascii "b"))
      (expect (hpack-table-count table) :to-equalp 1)
      (expect (hpack-table-size table) :to-equalp 34)
      (expect (hpack-table-find-exact table (ascii "a") (ascii "b"))
              :to-equalp 62)
      (hpack-table-insert table (ascii "c") (ascii "d"))
      (expect (hpack-table-count table) :to-equalp 1)
      (expect (hpack-table-entry-name (hpack-table-lookup table 62))
              :to-equalp
              (ascii "c"))))

  (it "clears the table when an entry exceeds the maximum size"
    (let ((table (make-hpack-table :maximum-size 32)))
      (hpack-table-insert table (ascii "a") (ascii "b"))
      (expect (hpack-table-count table) :to-equalp 0)
      (expect (hpack-table-size table) :to-equalp 0)))

  (it "keeps duplicate dynamic entries in newest-first index order"
    (let ((table (make-hpack-table :maximum-size 128)))
      (hpack-table-insert table (ascii "x") (ascii "one"))
      (hpack-table-insert table (ascii "x") (ascii "two"))
      (expect (hpack-table-count table) :to-equalp 2)
      (expect (hpack-table-find-exact table (ascii "x") (ascii "two"))
              :to-equalp
              62)
      (expect (hpack-table-find-exact table (ascii "x") (ascii "one"))
              :to-equalp
              63)
      (expect (hpack-table-find-name table (ascii "x")) :to-equalp 62)
      (expect (hpack-table-entry-value (hpack-table-lookup table 62))
              :to-equalp
              (ascii "two"))))

  (it "copies an existing entry and rejects a separate value"
    (let ((source (make-hpack-table))
          (target (make-hpack-table)))
      (hpack-table-insert source (ascii "x") (ascii "y"))
      (hpack-table-insert target (hpack-table-lookup source 62))
      (expect (hpack-table-entry-name (hpack-table-lookup target 62))
              :to-equalp
              (ascii "x"))
      (signals hpack-codec-error
        (hpack-table-insert target (hpack-table-lookup source 62) nil)))))

(describe "HPACK string literals"
  (it "round trips raw and Huffman string literals"
    (dolist (huffman '(nil t))
      (let ((encoded (hpack-encode-string (ascii "www.example.com")
                                          :huffman huffman)))
        (multiple-value-bind (decoded position encoded-huffman)
            (hpack-read-string encoded 0)
          (expect decoded :to-equalp (ascii "www.example.com"))
          (expect position :to-equalp (length encoded))
          (expect encoded-huffman :to-equalp huffman)))))
  (it "decodes a Huffman payload from the selected octet range"
    (let* ((encoded (hpack-huffman-encode (ascii "www.example.com")))
           (input (make-array (+ (length encoded) 2)
                              :element-type '(unsigned-byte 8)))
           (end (1+ (length encoded))))
      (setf (aref input 0) #xff
            (aref input end) 0)
      (replace input encoded :start1 1)
      (expect (hpack-codec::%hpack-huffman-decode-range input 1 end nil)
              :to-equalp
              (ascii "www.example.com"))))

  (it "supports arbitrary octets in a raw literal"
    (let ((input (octets 0 #x7f #x80 #xff)))
      (expect (hpack-read-string (hpack-encode-string input :huffman nil) 0)
              :to-equalp
              input)))

  (it "rejects truncated and overlong literals"
    (signals hpack-decoding-error
      (hpack-read-string (octets #x03 #x61) 0))
    (signals hpack-limit-error
      (hpack-read-string (octets #x03 #x61 #x62 #x63)
                         0
                         :maximum-length 2))))

(describe "HPACK RFC 7541 request examples"
  (it "matches the first Huffman request example"
    (let* ((headers (list (cons ":method" "GET")
                          (cons ":scheme" "http")
                          (cons ":path" "/")
                          (cons ":authority" "www.example.com")))
           (encoder (make-hpack-encoder :huffman t))
           (decoder (make-hpack-decoder))
           (block (hpack-encode-header-block encoder headers)))
      (expect block
              :to-equalp
              (octets #x82 #x86 #x84 #x41 #x8c #xf1 #xe3 #xc2 #xe5
                      #xf2 #x3a #x6b #xa0 #xab #x90 #xf4 #xff))
      (expect (header-pairs (hpack-decode-header-block decoder block))
              :to-equalp
              (list (list (ascii ":method") (ascii "GET"))
                    (list (ascii ":scheme") (ascii "http"))
                    (list (ascii ":path") (ascii "/"))
                    (list (ascii ":authority") (ascii "www.example.com"))))))

  (it "matches the second and third Huffman request examples"
    (let ((encoder (make-hpack-encoder :huffman t))
          (decoder (make-hpack-decoder)))
      (hpack-encode-header-block
       encoder
       (list (cons ":method" "GET")
             (cons ":scheme" "http")
             (cons ":path" "/")
             (cons ":authority" "www.example.com")))
      (expect
       (hpack-encode-header-block
        encoder
        (list (cons ":method" "GET")
              (cons ":scheme" "http")
              (cons ":path" "/index.html")
              (cons ":authority" "www.example.com")
              (cons "cache-control" "no-cache")))
       :to-equalp
       (octets #x82 #x86 #x85 #xbe #x58 #x86 #xa8 #xeb #x10 #x64 #x9c #xbf))
      (hpack-decode-header-block
       decoder
       (octets #x82 #x86 #x84 #x41 #x8c #xf1 #xe3 #xc2 #xe5
               #xf2 #x3a #x6b #xa0 #xab #x90 #xf4 #xff))
      (expect
       (hpack-encode-header-block
        encoder
        (list (cons ":method" "GET")
              (cons ":scheme" "https")
              (cons ":path" "/index.html")
              (cons ":authority" "www.example.com")
              (cons "custom-key" "custom-value")))
       :to-equalp
       (octets #x82 #x87 #x85 #xbf #x40 #x88 #x25 #xa8 #x49 #xe9 #x5b
               #xa9 #x7d #x7f #x89 #x25 #xa8 #x49 #xe9 #x5b #xb8 #xe8
               #xb4 #xbf))))

  (it "matches the first request example without Huffman coding"
    (let ((encoder (make-hpack-encoder :huffman nil)))
      (expect
       (hpack-encode-header-block
        encoder
        (list (cons ":method" "GET")
              (cons ":scheme" "http")
              (cons ":path" "/")
              (cons ":authority" "www.example.com")))
       :to-equalp
       (octets #x82 #x86 #x84 #x41 #x0f #x77 #x77 #x77 #x2e #x65 #x78
               #x61 #x6d #x70 #x6c #x65 #x2e #x63 #x6f #x6d))))

  (it "matches the complete raw request example sequence"
    (let* ((encoder (make-hpack-encoder :huffman nil))
           (decoder (make-hpack-decoder))
           (first-block
             (hpack-encode-header-block
              encoder
              (list (cons ":method" "GET")
                    (cons ":scheme" "http")
                    (cons ":path" "/")
                    (cons ":authority" "www.example.com"))))
           (second-block
             (hpack-encode-header-block
              encoder
              (list (cons ":method" "GET")
                    (cons ":scheme" "http")
                    (cons ":path" "/")
                    (cons ":authority" "www.example.com")
                    (cons "cache-control" "no-cache"))))
           (third-block
             (hpack-encode-header-block
              encoder
              (list (cons ":method" "GET")
                    (cons ":scheme" "https")
                    (cons ":path" "/index.html")
                    (cons ":authority" "www.example.com")
                    (cons "custom-key" "custom-value")))))
      (expect first-block
              :to-equalp
              (octets #x82 #x86 #x84 #x41 #x0f #x77 #x77 #x77 #x2e #x65
                      #x78 #x61 #x6d #x70 #x6c #x65 #x2e #x63 #x6f #x6d))
      (expect second-block
              :to-equalp
              (octets #x82 #x86 #x84 #xbe #x58 #x08 #x6e #x6f #x2d #x63
                      #x61 #x63 #x68 #x65))
      (expect third-block
              :to-equalp
              (octets #x82 #x87 #x85 #xbf #x40 #x0a #x63 #x75 #x73 #x74
                      #x6f #x6d #x2d #x6b #x65 #x79 #x0c #x63 #x75 #x73
                      #x74 #x6f #x6d #x2d #x76 #x61 #x6c #x75 #x65))
      (expect (length (hpack-decode-header-block decoder first-block))
              :to-equalp
              4)
      (expect (length (hpack-decode-header-block decoder second-block))
              :to-equalp
              5)
      (expect (length (hpack-decode-header-block decoder third-block))
              :to-equalp
              5))))

(describe "HPACK RFC 7541 response examples"
  (it "matches the raw and Huffman response example sequences"
    (let* ((header-lists
             (list
              (list (cons ":status" "302")
                    (cons "cache-control" "private")
                    (cons "date" "Mon, 21 Oct 2013 20:13:21 GMT")
                    (cons "location" "https://www.example.com"))
              (list (cons ":status" "307")
                    (cons "cache-control" "private")
                    (cons "date" "Mon, 21 Oct 2013 20:13:21 GMT")
                    (cons "location" "https://www.example.com"))
              (list (cons ":status" "200")
                    (cons "cache-control" "private")
                    (cons "date" "Mon, 21 Oct 2013 20:13:22 GMT")
                    (cons "location" "https://www.example.com")
                    (cons "content-encoding" "gzip")
                    (cons "set-cookie"
                          "foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; max-age=3600; version=1"))))
           (raw-blocks
             (list
              (octets #x48 #x03 #x33 #x30 #x32 #x58 #x07 #x70 #x72 #x69
                      #x76 #x61 #x74 #x65 #x61 #x1d #x4d #x6f #x6e #x2c
                      #x20 #x32 #x31 #x20 #x4f #x63 #x74 #x20 #x32 #x30
                      #x31 #x33 #x20 #x32 #x30 #x3a #x31 #x33 #x3a #x32
                      #x31 #x20 #x47 #x4d #x54 #x6e #x17 #x68 #x74 #x74
                      #x70 #x73 #x3a #x2f #x2f #x77 #x77 #x77 #x2e #x65
                      #x78 #x61 #x6d #x70 #x6c #x65 #x2e #x63 #x6f #x6d)
              (octets #x48 #x03 #x33 #x30 #x37 #xc1 #xc0 #xbf)
              (octets #x88 #xc1 #x61 #x1d #x4d #x6f #x6e #x2c #x20 #x32
                      #x31 #x20 #x4f #x63 #x74 #x20 #x32 #x30 #x31 #x33
                      #x20 #x32 #x30 #x3a #x31 #x33 #x3a #x32 #x32 #x20
                      #x47 #x4d #x54 #xc0 #x5a #x04 #x67 #x7a #x69 #x70
                      #x77 #x38 #x66 #x6f #x6f #x3d #x41 #x53 #x44 #x4a
                      #x4b #x48 #x51 #x4b #x42 #x5a #x58 #x4f #x51 #x57
                      #x45 #x4f #x50 #x49 #x55 #x41 #x58 #x51 #x57 #x45
                      #x4f #x49 #x55 #x3b #x20 #x6d #x61 #x78 #x2d #x61
                      #x67 #x65 #x3d #x33 #x36 #x30 #x30 #x3b #x20 #x76
                      #x65 #x72 #x73 #x69 #x6f #x6e #x3d #x31)))
           (huffman-blocks
             (list
              (octets #x48 #x82 #x64 #x02 #x58 #x85 #xae #xc3 #x77 #x1a
                      #x4b #x61 #x96 #xd0 #x7a #xbe #x94 #x10 #x54 #xd4
                      #x44 #xa8 #x20 #x05 #x95 #x04 #x0b #x81 #x66 #xe0
                      #x82 #xa6 #x2d #x1b #xff #x6e #x91 #x9d #x29 #xad
                      #x17 #x18 #x63 #xc7 #x8f #x0b #x97 #xc8 #xe9 #xae
                      #x82 #xae #x43 #xd3)
              (octets #x48 #x83 #x64 #x0e #xff #xc1 #xc0 #xbf)
              (octets #x88 #xc1 #x61 #x96 #xd0 #x7a #xbe #x94 #x10 #x54
                      #xd4 #x44 #xa8 #x20 #x05 #x95 #x04 #x0b #x81 #x66
                      #xe0 #x84 #xa6 #x2d #x1b #xff #xc0 #x5a #x83 #x9b
                      #xd9 #xab #x77 #xad #x94 #xe7 #x82 #x1d #xd7 #xf2
                      #xe6 #xc7 #xb3 #x35 #xdf #xdf #xcd #x5b #x39 #x60
                      #xd5 #xaf #x27 #x08 #x7f #x36 #x72 #xc1 #xab #x27
                      #x0f #xb5 #x29 #x1f #x95 #x87 #x31 #x60 #x65 #xc0
                      #x03 #xed #x4e #xe5 #xb1 #x06 #x3d #x50 #x07))))
      (dolist (huffman '(nil t))
        (let ((encoder (make-hpack-encoder :maximum-table-size 256
                                            :huffman huffman))
              (decoder (make-hpack-decoder :maximum-table-size 256))
              (blocks (if huffman huffman-blocks raw-blocks)))
          (loop for headers in header-lists
                for expected-block in blocks
                do (expect (hpack-encode-header-block encoder headers)
                           :to-equalp
                           expected-block)
                   (expect (header-pairs
                            (hpack-decode-header-block decoder expected-block))
                           :to-equalp
                           (mapcar (lambda (header)
                                     (list (ascii (car header))
                                           (ascii (cdr header))))
                                   headers))))))))

(describe "HPACK representations and state"
  (it "exposes public predicates for stateful codecs"
    (let ((encoder (make-hpack-encoder))
          (decoder (make-hpack-decoder)))
      (expect (hpack-encoder-p encoder) :to-equalp t)
      (expect (hpack-decoder-p decoder) :to-equalp t)
      (expect (hpack-encoder-p decoder) :to-equalp nil)
      (expect (hpack-decoder-p encoder) :to-equalp nil)))

  (it "encodes indexed and incremental-indexing representations"
    (let* ((encoder (make-hpack-encoder :huffman nil))
           (decoder (make-hpack-decoder))
           (indexed-block
             (hpack-encode-header-block
              encoder
              (list (make-hpack-header :name ":method"
                                       :value "GET"
                                       :representation :indexed))))
           (indexed (first (hpack-decode-header-block decoder indexed-block)))
           (incremental-block
             (hpack-encode-header-block
              encoder
              (list (make-hpack-header :name "x"
                                       :value "y"
                                       :representation :incremental-indexing))))
           (incremental
             (first (hpack-decode-header-block decoder incremental-block))))
      (expect indexed-block :to-equalp (octets #x82))
      (expect (hpack-header-representation indexed) :to-equalp :indexed)
      (expect (aref incremental-block 0) :to-equalp #x40)
      (expect (hpack-header-representation incremental)
              :to-equalp
              :incremental-indexing)
      (expect (hpack-table-count (hpack-encoder-table encoder)) :to-equalp 1)
      (expect (hpack-table-count (hpack-decoder-table decoder)) :to-equalp 1)))

  (it "preserves without-indexing and never-indexed representations"
    (dolist (representation '(:without-indexing :never-indexed))
      (let* ((encoder (make-hpack-encoder :huffman nil))
             (decoder (make-hpack-decoder))
             (header (make-hpack-header :name "x"
                                        :value "y"
                                        :representation representation))
             (block (hpack-encode-header-block encoder (list header)))
             (decoded (first (hpack-decode-header-block decoder block))))
        (expect (aref block 0)
                :to-equalp
                (if (eq representation :never-indexed) #x10 0))
        (expect (hpack-header-representation decoded)
                :to-equalp
                representation)
        (expect (hpack-table-count (hpack-encoder-table encoder))
                :to-equalp
                0)
        (expect (hpack-table-count (hpack-decoder-table decoder))
                :to-equalp
                0))))

  (it "accepts a three-element header list with an explicit representation"
    (let ((block (hpack-encode-header-block
                  (make-hpack-encoder :huffman nil)
                  (list (list "x" "y" :never-indexed)))))
      (expect block :to-equalp (octets #x10 #x01 #x78 #x01 #x79))))

  (it "emits and applies dynamic table size updates"
    (let ((encoder (make-hpack-encoder))
          (decoder (make-hpack-decoder)))
      (hpack-encoder-set-table-size encoder 0)
      (hpack-encoder-set-table-size encoder 128)
      (let ((block (hpack-encode-header-block encoder nil)))
        (expect block :to-equalp (octets #x20 #x3f #x61))
        (expect (hpack-decode-header-block decoder block) :to-equalp nil)
        (expect (hpack-table-maximum-size (hpack-decoder-table decoder))
                :to-equalp
                128))))

  (it "rolls back dynamic table state when encoding fails"
    (let ((encoder (make-hpack-encoder :huffman nil :maximum-block-size 1)))
      (signals hpack-limit-error
        (hpack-encode-header-block encoder (list (cons "x" "y"))))
      (expect (hpack-table-count (hpack-encoder-table encoder))
              :to-equalp
              0)))

  (it "rolls back dynamic table state when decoding fails"
    (let ((decoder (make-hpack-decoder)))
      (signals hpack-decoding-error
        (hpack-decode-header-block
         decoder
         (octets #x40 #x01 #x61 #x01 #x62 #x40 #x01 #x63)))
      (expect (hpack-table-count (hpack-decoder-table decoder))
              :to-equalp
              0))))

(describe "HPACK fragmented decoding"
  (it "buffers fragments and commits only when finish succeeds"
    (let* ((decoder (make-hpack-decoder))
           (block (octets #x40 #x01 #x61 #x01 #x62)))
      (expect (hpack-decoder-feed decoder (subseq block 0 2)) :to-equalp 2)
      (expect (hpack-decoder-buffered-size decoder) :to-equalp 2)
      (expect (hpack-table-count (hpack-decoder-table decoder)) :to-equalp 0)
      (expect (hpack-decoder-feed decoder (subseq block 2))
              :to-equalp
              (length block))
      (expect (header-pairs (hpack-decoder-finish decoder))
              :to-equalp
              (list (list (ascii "a") (ascii "b"))))
      (expect (hpack-decoder-buffered-size decoder) :to-equalp 0)
      (expect (hpack-table-count (hpack-decoder-table decoder)) :to-equalp 1)))

  (it "retains failed fragments and applies finish options"
    (let ((decoder (make-hpack-decoder)))
      (hpack-decoder-feed decoder (octets #x40 #x01 #x61))
      (signals hpack-decoding-error
        (hpack-decoder-finish decoder))
      (expect (hpack-decoder-buffered-size decoder) :to-equalp 3)
      (expect (hpack-table-count (hpack-decoder-table decoder)) :to-equalp 0)
      (expect (eq (hpack-decoder-abort decoder) decoder) :to-equalp t)
      (expect (hpack-decoder-buffered-size decoder) :to-equalp 0))
    (let ((decoder (make-hpack-decoder)))
      (hpack-decoder-feed decoder (octets #x82))
      (signals hpack-limit-error
        (hpack-decoder-finish decoder :max-fields 1 :max-header-bytes 41))
      (expect (hpack-decoder-buffered-size decoder) :to-equalp 1)
      (expect (header-pairs
               (hpack-decoder-finish
                decoder :max-fields 1 :max-header-bytes 42))
              :to-equalp
              (list (list (ascii ":method") (ascii "GET"))))
      (expect (hpack-decoder-buffered-size decoder) :to-equalp 0))
    (let ((decoder (make-hpack-decoder)))
      (hpack-decoder-feed decoder (octets #x00 #x01 #x58 #x01 #x79))
      (signals hpack-decoding-error
        (hpack-decoder-finish decoder :validate-header-names t))
      (expect (hpack-decoder-buffered-size decoder) :to-equalp 5)
      (hpack-decoder-abort decoder)))

  (it "rejects fragments beyond the block limit before buffering them"
    (let ((decoder (make-hpack-decoder :maximum-block-size 2)))
      (hpack-decoder-feed decoder (octets #x82 #x86))
      (signals hpack-limit-error
        (hpack-decoder-feed decoder (octets #x84)))
      (expect (hpack-decoder-buffered-size decoder) :to-equalp 2))))

(describe "HPACK malformed input and resource limits"
  (it "rejects duplicate keyword arguments"
    (signals hpack-codec-error
      (make-hpack-header :name "a" :name "b" :value "c"))
    (signals hpack-codec-error
      (make-hpack-table :maximum-size 1 :max-size 2)))

  (it "rejects extra positional header arguments"
    (signals hpack-codec-error
      (make-hpack-header "a" "b" :auto :unexpected)))

  (it "rejects improper and circular header sequences"
    (signals hpack-codec-error
      (hpack-encode-header-block
       (make-hpack-encoder)
       (cons (cons "a" "b") (cons "c" "d"))))
    (let ((headers (list (cons "a" "b"))))
      (setf (cdr headers) headers)
      (signals hpack-codec-error
        (hpack-encode-header-block (make-hpack-encoder) headers)))
    (let ((headers (list (cons "a" "b"))))
      (setf (cdr (first headers)) (first headers))
      (signals hpack-codec-error
        (hpack-encode-header-block (make-hpack-encoder) headers)))
    (signals hpack-codec-error
      (hpack-encode-header-block
       (make-hpack-encoder)
       (list (cons "a" (cons "b" "c"))))))

  (it "rejects invalid indices and illegal update placement"
    (signals hpack-decoding-error
      (hpack-decode-header-block (make-hpack-decoder) (octets #x80)))
    (signals hpack-decoding-error
      (hpack-decode-header-block (make-hpack-decoder) (octets #x82 #x20)))
    (signals hpack-decoding-error
      (hpack-decode-header-block
       (make-hpack-decoder)
       (octets #x20 #x20 #x20))))

  (it "enforces encoder and decoder limits"
    (signals hpack-limit-error
      (hpack-encode-header-block
       (make-hpack-encoder :maximum-field-count 1)
       (list (cons "a" "b") (cons "c" "d"))))
    (signals hpack-limit-error
      (hpack-encode-header-block
       (make-hpack-encoder :maximum-header-list-size 33)
       (list (cons "a" "b"))))
    (signals hpack-limit-error
      (hpack-decode-header-block
       (make-hpack-decoder :maximum-block-size 1)
       (octets #x82 #x82)))
    (signals hpack-decoding-error
      (hpack-decode-header-block
       (make-hpack-decoder :maximum-table-size 0)
       (octets #x21)))))
(describe "HPACK Phase 3a APIs"
  (it "validates HTTP/2 header names when enabled"
    (expect (hpack-valid-header-name-p ":method") :to-equalp t)
    (expect (hpack-valid-header-name-p ":foo") :to-equalp t)
    (expect (hpack-valid-header-name-p "content-type") :to-equalp t)
    (expect (hpack-valid-header-name-p "Content-Type") :to-equalp nil)
    (expect (hpack-valid-header-name-p "bad name") :to-equalp nil)
    (expect (hpack-valid-header-name-p (vector #\x)) :to-equalp nil)
    (let ((block (octets #x00 #x01 #x58 #x01 #x79))
          (pseudo-block
            (octets #x00 #x04 #x3a #x66 #x6f #x6f #x01 #x78)))
      (expect (length (hpack-decode-header-block (make-hpack-decoder) block))
              :to-equalp
              1)
      (signals hpack-decoding-error
        (hpack-decode-header-block
         (make-hpack-decoder)
         block
         :validate-header-names t))
      (signals hpack-decoding-error
        (hpack-decode-header-block
         (make-hpack-decoder :validate-header-names t)
         block))
      (signals hpack-decoding-error
        (hpack-decode-header-block
         (make-hpack-decoder :validate-header-names t)
         block
         :validate-header-names nil))
      (expect
       (header-pairs
        (hpack-decode-header-block
         (make-hpack-decoder :validate-header-names t)
         pseudo-block))
       :to-equalp
       (list (list (ascii ":foo") (ascii "x"))))))

  (it "applies per-call decode limits without changing decoder defaults"
    (let* ((decoder (make-hpack-decoder
                     :maximum-field-count 2
                     :maximum-header-list-size 84))
           (one-field (octets #x82))
           (two-fields (octets #x82 #x82))
           (three-fields (octets #x82 #x82 #x82))
           (large-field-block
             (hpack-encode-header-block
              (make-hpack-encoder :huffman nil)
              (list (cons "x" (make-string 53 :initial-element #\a))))))
      (signals hpack-limit-error
        (hpack-decode-header-block decoder two-fields :max-fields 1))
      (expect (hpack-decoder-maximum-field-count decoder) :to-equalp 2)
      (expect (length (hpack-decode-header-block decoder two-fields))
              :to-equalp
              2)
      (signals hpack-limit-error
        (hpack-decode-header-block decoder three-fields :max-fields 3))
      (signals hpack-limit-error
        (hpack-decode-header-block decoder one-field :max-header-bytes 41))
      (expect (length (hpack-decode-header-block
                       decoder one-field :max-header-bytes 42))
              :to-equalp
              1)
      (signals hpack-limit-error
        (hpack-decode-header-block decoder two-fields :max-header-bytes 83))
      (expect (hpack-decoder-maximum-header-list-size decoder)
              :to-equalp
              84)
      (expect (length (hpack-decode-header-block
                       decoder one-field :max-header-bytes 100))
              :to-equalp
              1)
      (signals hpack-limit-error
        (hpack-decode-header-block decoder large-field-block
                                   :max-header-bytes 100))
      (signals hpack-limit-error
        (hpack-decode-header-block
         (make-hpack-decoder)
         large-field-block
         :max-header-bytes 85))
      (expect (length (hpack-decode-header-block
                       (make-hpack-decoder)
                       large-field-block
                       :max-header-bytes 86))
              :to-equalp
              1)
      (expect (length (hpack-decode-header-block decoder one-field))
              :to-equalp
              1)))

  (it "uses never-indexed for predicate-matched stateful fields"
    (let* ((encoder (make-hpack-encoder :huffman nil))
           (decoder (make-hpack-decoder))
           (header (make-hpack-header :name ":method"
                                      :value "GET"
                                      :representation :indexed))
           (block
             (hpack-encode-header-block
              encoder
              (list header)
              :sensitive-predicate
              (lambda (name value)
                (and (equalp name (ascii ":method"))
                     (equalp value (ascii "GET"))))))
           (decoded (first (hpack-decode-header-block decoder block))))
      (expect block :to-equalp (octets #x12 #x03 #x47 #x45 #x54))
      (expect (hpack-header-representation decoded)
              :to-equalp
              :never-indexed)
      (expect (hpack-table-count (hpack-encoder-table encoder)) :to-equalp 0)
      (expect (hpack-table-count (hpack-decoder-table decoder)) :to-equalp 0)))

  (it "encodes only static matches and applies limits without retaining state"
    (let* ((static-header (make-hpack-header :name ":method" :value "GET"))
           (literal-header
             (make-hpack-header :name "x"
                                :value "y"
                                :representation :incremental-indexing))
           (headers (list static-header literal-header))
           (block (hpack-encode-static-header-block headers :huffman nil))
           (decoder (make-hpack-decoder))
           (decoded (hpack-decode-header-block decoder block))
           (repeated-block
             (hpack-encode-static-header-block headers :huffman nil)))
      (expect block :to-equalp (octets #x82 #x00 #x01 #x78 #x01 #x79))
      (expect repeated-block :to-equalp block)
      (expect (mapcar #'hpack-header-representation decoded)
              :to-equalp
              '(:indexed :without-indexing))
      (expect (hpack-header-representation static-header)
              :to-equalp
              :auto)
      (expect (hpack-header-representation literal-header)
              :to-equalp
              :incremental-indexing)
      (expect (hpack-table-count (hpack-decoder-table decoder)) :to-equalp 0)
      (let* ((sensitive-header
               (make-hpack-header :name ":method"
                                  :value "GET"
                                  :representation :indexed))
             (sensitive-block
               (hpack-encode-static-header-block
                (list sensitive-header)
                :huffman nil
                :sensitive-predicate (lambda (name value)
                                       (declare (ignore name value))
                                       t)))
             (sensitive-decoded
               (first (hpack-decode-header-block decoder sensitive-block))))
        (expect sensitive-block
                :to-equalp
                (octets #x12 #x03 #x47 #x45 #x54))
        (expect (hpack-header-representation sensitive-decoded)
                :to-equalp
                :never-indexed)
        (expect (hpack-header-representation sensitive-header)
                :to-equalp
                :indexed)
        (expect (hpack-table-count (hpack-decoder-table decoder))
                :to-equalp
                0))
      (signals hpack-limit-error
        (hpack-encode-static-header-block
         (list (cons "x" "y") (cons "a" "b"))
         :huffman nil
         :maximum-field-count 1))
      (signals hpack-limit-error
        (hpack-encode-static-header-block
         (list (cons "x" "y"))
         :huffman nil
         :maximum-header-list-size 33))
      (signals hpack-limit-error
        (hpack-encode-static-header-block
         (list (cons "x" "yy"))
         :huffman nil
         :maximum-string-length 1))
      (signals hpack-limit-error
        (hpack-encode-static-header-block
         (list (cons "x" "y"))
         :huffman nil
         :maximum-block-size 4))
      (expect
       (length
        (hpack-encode-static-header-block
         (list (cons "x" "y"))
         :huffman nil
         :maximum-field-count 1
         :maximum-header-list-size 34
         :maximum-string-length 1
         :maximum-block-size 5))
       :to-equalp
       5)))

  (it "enforces decoder table size changes made by the local setting"
    (let ((decoder (make-hpack-decoder :maximum-table-size 128)))
      (expect (hpack-decoder-maximum-table-size decoder) :to-equalp 128)
      (hpack-decode-header-block decoder (octets #x40 #x01 #x61 #x01 #x62))
      (expect (hpack-table-count (hpack-decoder-table decoder)) :to-equalp 1)
      (expect (eq (hpack-decoder-set-table-size decoder 32) decoder)
              :to-equalp
              t)
      (expect (hpack-decoder-maximum-table-size decoder) :to-equalp 32)
      (expect (hpack-table-maximum-size (hpack-decoder-table decoder))
              :to-equalp
              32)
      (expect (hpack-table-count (hpack-decoder-table decoder)) :to-equalp 0)
      (signals hpack-decoding-error
        (hpack-decode-header-block decoder (octets #x3f #x21)))
      (expect (hpack-table-maximum-size (hpack-decoder-table decoder))
              :to-equalp
              32)
      (hpack-decoder-set-table-size decoder 64)
      (expect (hpack-decode-header-block decoder (octets #x3f #x21))
              :to-equalp
              nil)
      (expect (hpack-decoder-maximum-table-size decoder) :to-equalp 64)
      (expect (hpack-table-maximum-size (hpack-decoder-table decoder))
              :to-equalp
              64)))
  (it "limits Huffman literal output before committing decoder state"
    (let* ((decoder (make-hpack-decoder))
           (seed-block
             (hpack-encode-header-block
              (make-hpack-encoder :huffman nil)
              (list (cons "seed" "state"))))
           (oversized-block
             (hpack-encode-header-block
              (make-hpack-encoder :huffman t)
              (list
               (cons "x"
                     (make-string 1024 :initial-element #\a))))))
      (expect (length (hpack-decode-header-block decoder seed-block))
              :to-equalp
              1)
      (expect (hpack-table-count (hpack-decoder-table decoder)) :to-equalp 1)
      (signals hpack-limit-error
        (hpack-decode-header-block
         decoder oversized-block :max-header-bytes 40))
      (expect (hpack-table-count (hpack-decoder-table decoder)) :to-equalp 1)
      (expect
       (hpack-table-entry-name
        (hpack-table-lookup (hpack-decoder-table decoder) 62))
       :to-equalp
       (ascii "seed"))
      (expect
       (hpack-table-entry-value
        (hpack-table-lookup (hpack-decoder-table decoder) 62))
       :to-equalp
       (ascii "state")))))
