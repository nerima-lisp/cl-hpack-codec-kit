(defpackage #:hpack-codec
  (:use #:cl)
  (:export
   ;; Conditions
   #:hpack-codec-error
   #:hpack-codec-error-message
   #:hpack-codec-error-operation
   #:hpack-codec-error-detail
   #:hpack-decoding-error
   #:hpack-limit-error
   ;; Header fields and table state
   #:hpack-header
   #:hpack-header-p
   #:make-hpack-header
   #:hpack-header-name
   #:hpack-header-value
   #:hpack-header-representation
   #:hpack-table
   #:hpack-table-p
   #:make-hpack-table
   #:hpack-table-count
   #:hpack-table-entry
   #:hpack-table-entry-p
   #:hpack-table-entry-name
   #:hpack-table-entry-value
   #:hpack-table-lookup
   #:hpack-table-find-exact
   #:hpack-table-find-name
   #:hpack-table-size
   #:hpack-table-current-size
   #:hpack-table-maximum-size
   #:hpack-table-set-maximum-size
   #:hpack-table-update-maximum-size
   #:hpack-table-insert
   #:hpack-table-evict
   #:hpack-table-evict-oldest
   #:hpack-table-evict-to-size
   #:hpack-table-copy
   #:hpack-static-table-count
   #:hpack-static-table-entry
   #:hpack-static-table
   ;; Huffman coding
   #:hpack-huffman-encode
   #:hpack-huffman-decode
   #:hpack-encode-string
   #:hpack-read-string
   ;; Prefixed integer coding
   #:hpack-encode-integer
   #:hpack-read-integer
   ;; Stateful header block codec
   #:hpack-encoder
   #:hpack-encoder-p
   #:make-hpack-encoder
   #:hpack-encoder-table
   #:hpack-encoder-maximum-table-size
   #:hpack-encoder-huffman
   #:hpack-encoder-maximum-block-size
   #:hpack-encoder-maximum-header-list-size
   #:hpack-encoder-maximum-field-count
   #:hpack-encoder-maximum-string-length
   #:hpack-encoder-set-table-size
   #:hpack-encode-header-block
   #:hpack-decoder
   #:hpack-decoder-p
   #:make-hpack-decoder
   #:hpack-decoder-table
   #:hpack-decoder-maximum-table-size
   #:hpack-decoder-maximum-block-size
   #:hpack-decoder-maximum-header-list-size
   #:hpack-decoder-maximum-field-count
   #:hpack-decoder-maximum-string-length
   #:hpack-decoder-set-table-size
   #:hpack-decoder-buffered-size
   #:hpack-decoder-feed
   #:hpack-decoder-finish
   #:hpack-decoder-abort
   #:hpack-decode-header-block))
