(in-package #:hpack-codec)

(defun %hpack-encode-index (index prefix-bits prefix)
  (hpack-encode-integer index prefix-bits prefix))

(defun %hpack-encode-literal (table header representation huffman maximum-string-length)
  (let* ((name (hpack-header-name header))
         (value (hpack-header-value header))
         (name-index (hpack-table-find-name table name))
         (prefix-bits (if (eq representation :incremental-indexing) 6 4))
         (prefix (case representation
                   (:incremental-indexing #x40)
                   (:without-indexing 0)
                   (:never-indexed #x10)
                   (otherwise
                    (%hpack-block-error
                     "Invalid HPACK literal representation."
                     :hpack-header
                     representation)))))
    (let ((name-octets
            (if name-index
                (%hpack-encode-index name-index prefix-bits prefix)
                (%hpack-append-octets
                 (list (%hpack-encode-index 0 prefix-bits prefix)
                       (hpack-encode-string
                        name
                        :huffman huffman
                        :maximum-length maximum-string-length)))))
          (value-octets
            (hpack-encode-string
             value
             :huffman huffman
             :maximum-length maximum-string-length)))
      (when (eq representation :incremental-indexing)
        (hpack-table-insert table name value))
      (%hpack-append-octets (list name-octets value-octets)))))

(defun %hpack-encode-header (table header huffman maximum-string-length)
  (let* ((name (hpack-header-name header))
         (value (hpack-header-value header))
         (representation (hpack-header-representation header))
         (exact-index (hpack-table-find-exact table name value)))
      (case representation
      (:indexed
       (unless exact-index
         (%hpack-block-error
          "An indexed HPACK representation requires an indexed field."
          :hpack-header
          header))
       (%hpack-encode-index exact-index 7 #x80))
      (:auto
       (if exact-index
           (%hpack-encode-index exact-index 7 #x80)
           (%hpack-encode-literal
            table header :incremental-indexing huffman maximum-string-length)))
      ((:incremental-indexing :without-indexing :never-indexed)
       (%hpack-encode-literal
        table header representation huffman maximum-string-length))
      (otherwise
       (%hpack-block-error
        "Unknown HPACK header representation."
        :hpack-header
        representation)))))
