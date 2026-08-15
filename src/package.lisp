(defpackage #:hpack-codec
  (:use #:cl)
  (:export
   ;; Conditions
   #:hpack-codec-error
   #:hpack-codec-error-message
   #:hpack-codec-error-operation
   #:hpack-codec-error-detail
   ;; Huffman coding
   #:hpack-huffman-encode
   #:hpack-huffman-decode
   ;; Prefixed integer coding
   #:hpack-encode-integer
   #:hpack-read-integer))
