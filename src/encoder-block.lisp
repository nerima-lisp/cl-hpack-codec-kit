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
    (encoder headers &key (huffman nil huffman-supplied-p)
                          sensitive-predicate)
  "Encode HEADERS using ENCODER and return a fresh HPACK header block.

SENSITIVE-PREDICATE receives each normalized header name and value as octet
vectors. A matching field uses the never-indexed representation."
  (%ensure-encoder encoder)
  (unless (or (null sensitive-predicate) (functionp sensitive-predicate))
    (%hpack-block-error
     "The HPACK sensitive predicate must be a function."
     :hpack-header-block
     sensitive-predicate))
  (let* ((normalized-headers
           (%hpack-normalize-headers
            headers
            (hpack-encoder-maximum-header-list-size encoder)
            (hpack-encoder-maximum-field-count encoder)))
         (headers
           (mapcar
            (lambda (header)
              (when (and sensitive-predicate
                         (funcall sensitive-predicate
                                  (hpack-header-name header)
                                  (hpack-header-value header)))
                (setf (hpack-header-representation header) :never-indexed))
              header)
            normalized-headers))
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
(defun hpack-encode-static-header-block
    (headers &key (huffman :auto) sensitive-predicate
                  (maximum-header-list-size *hpack-default-maximum-header-list-size*)
                  (maximum-field-count *hpack-default-maximum-field-count*)
                  (maximum-string-length *hpack-default-maximum-string-length*)
                  (maximum-block-size *hpack-default-maximum-block-size*))
  "Encode HEADERS with static-table indexing and no dynamic table state."
  (unless (or (null sensitive-predicate) (functionp sensitive-predicate))
    (%hpack-block-error
     "The HPACK sensitive predicate must be a function."
     :hpack-header-block
     sensitive-predicate))
  (let* ((maximum-header-list-size
           (%hpack-ensure-limit maximum-header-list-size
                                :maximum-header-list-size))
         (maximum-field-count
           (%hpack-ensure-limit maximum-field-count :maximum-field-count))
         (maximum-string-length
           (%hpack-ensure-limit maximum-string-length :maximum-string-length))
         (maximum-block-size
           (%hpack-ensure-limit maximum-block-size :maximum-block-size))
         (headers
           (%hpack-normalize-headers
            headers maximum-header-list-size maximum-field-count))
         (table (make-hpack-table :maximum-size 0))
         (huffman (%hpack-ensure-huffman-option huffman))
         (headers
           (mapcar
            (lambda (header)
              (let* ((name (hpack-header-name header))
                     (value (hpack-header-value header))
                     (exact-index (hpack-table-find-exact table name value))
                     (sensitive-p
                       (and sensitive-predicate
                            (funcall sensitive-predicate name value)))
                     (representation
                       (hpack-header-representation header)))
                (cond
                  (sensitive-p
                   (setf representation :never-indexed))
                  ((eq representation :auto)
                   (setf representation
                         (if exact-index :indexed :without-indexing)))
                  ((eq representation :incremental-indexing)
                   (setf representation :without-indexing)))
                (setf (hpack-header-representation header) representation)
                header))
            headers))
         (pieces
           (loop for header in headers
                 collect (%hpack-encode-header
                          table header huffman maximum-string-length)))
         (result (%hpack-append-octets pieces)))
    (when (> (length result) maximum-block-size)
      (%hpack-block-limit-error
       "The HPACK header block exceeds its limit."
       :hpack-header-block
       maximum-block-size))
    result))
