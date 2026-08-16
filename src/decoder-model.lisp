(in-package #:hpack-codec)

(defun make-hpack-decoder (&rest arguments)
  (%hpack-check-keywords
   arguments
   '(:maximum-table-size :maximum-block-size :maximum-header-list-size
     :maximum-field-count :maximum-string-length)
   :hpack-decoder)
  (let ((maximum-table-size
          (%ensure-table-size (getf arguments :maximum-table-size 4096)
                              "Decoder maximum table size"))
        (maximum-block-size
          (%hpack-ensure-limit
           (getf arguments :maximum-block-size
                *hpack-default-maximum-block-size*)
           :maximum-block-size))
        (maximum-header-list-size
          (%hpack-ensure-limit
           (getf arguments :maximum-header-list-size
                *hpack-default-maximum-header-list-size*)
           :maximum-header-list-size))
        (maximum-field-count
          (%hpack-ensure-limit
           (getf arguments :maximum-field-count *hpack-default-maximum-field-count*)
           :maximum-field-count))
        (maximum-string-length
          (%hpack-ensure-limit
           (getf arguments :maximum-string-length
                *hpack-default-maximum-string-length*)
           :maximum-string-length)))
    (%make-hpack-decoder
     :table (make-hpack-table :maximum-size maximum-table-size)
     :maximum-table-size maximum-table-size
     :maximum-block-size maximum-block-size
     :maximum-header-list-size maximum-header-list-size
     :maximum-field-count maximum-field-count
     :maximum-string-length maximum-string-length
     :pending-octets (make-array 0 :element-type '(unsigned-byte 8)))))

(defun %ensure-decoder (decoder)
  (unless (hpack-decoder-p decoder)
    (%hpack-block-error "Value must be an HPACK decoder." :hpack-decoder decoder))
  decoder)

(defun %hpack-account-decoded-header (decoder header field-count header-list-size)
  (let ((new-field-count (1+ field-count))
        (new-header-list-size
          (+ header-list-size
             32
             (length (hpack-header-name header))
             (length (hpack-header-value header)))))
    (let ((maximum-field-count
            (hpack-decoder-maximum-field-count decoder))
          (maximum-header-list-size
            (hpack-decoder-maximum-header-list-size decoder)))
      (when (> new-field-count maximum-field-count)
        (%hpack-block-limit-error
         "The HPACK header field count exceeds its limit."
         :hpack-header-block
         maximum-field-count))
      (when (> new-header-list-size maximum-header-list-size)
        (%hpack-block-limit-error
         "The HPACK header list exceeds its limit."
         :hpack-header-block
         maximum-header-list-size)))
    (values new-field-count new-header-list-size)))

(defun hpack-decoder-set-table-size (decoder maximum-table-size)
  (%ensure-decoder decoder)
  (%ensure-table-size maximum-table-size "Decoder maximum table size")
  (setf (hpack-decoder-maximum-table-size decoder) maximum-table-size)
  (when (> (hpack-table-maximum-size (hpack-decoder-table decoder))
           maximum-table-size)
    (hpack-table-set-maximum-size (hpack-decoder-table decoder)
                                  maximum-table-size))
  decoder)
