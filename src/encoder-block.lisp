(in-package #:hpack-codec)

(defun %hpack-pending-size-updates (encoder)
  (let ((minimum (hpack-encoder-pending-minimum-table-size encoder))
        (final (hpack-encoder-pending-final-table-size encoder)))
    (cond
      ((null minimum) nil)
      ((= minimum final)
       (list (%hpack-encode-index minimum 5 #x20)))
      (t
       (list (%hpack-encode-index minimum 5 #x20)
             (%hpack-encode-index final 5 #x20))))))

(defun hpack-encode-header-block
    (encoder headers &key (huffman nil huffman-supplied-p))
  "Encode HEADERS using ENCODER and return a fresh HPACK header block."
  (%ensure-encoder encoder)
  (let* ((headers (%hpack-normalize-headers
                   headers
                   (hpack-encoder-maximum-header-list-size encoder)
                   (hpack-encoder-maximum-field-count encoder)))
         (huffman (if huffman-supplied-p
                      huffman
                      (hpack-encoder-huffman encoder)))
         (huffman (%hpack-ensure-huffman-option huffman))
         (table (hpack-table-copy (hpack-encoder-table encoder)))
         (pieces (%hpack-pending-size-updates encoder)))
    (setf pieces
          (append
           pieces
           (loop for header in headers
                 collect (%hpack-encode-header
                          table header huffman
                          (hpack-encoder-maximum-string-length encoder)))))
    (let ((result (%hpack-append-octets pieces)))
      (when (> (length result) (hpack-encoder-maximum-block-size encoder))
        (%hpack-block-limit-error
         "The HPACK header block exceeds its limit."
         :hpack-header-block
         (hpack-encoder-maximum-block-size encoder)))
      (setf (hpack-encoder-table encoder) table
            (hpack-encoder-pending-minimum-table-size encoder) nil
            (hpack-encoder-pending-final-table-size encoder) nil)
      result)))
