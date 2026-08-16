(in-package #:hpack-codec)

(defun make-hpack-encoder (&rest arguments)
  (%hpack-check-keywords
   arguments
   '(:maximum-table-size :huffman :maximum-block-size
     :maximum-header-list-size :maximum-field-count :maximum-string-length)
   :hpack-encoder)
  (let ((maximum-table-size
          (%ensure-table-size (getf arguments :maximum-table-size 4096)
                              "Encoder maximum table size"))
        (huffman (%hpack-ensure-huffman-option
                  (getf arguments :huffman :auto)))
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
    (%make-hpack-encoder
     :table (make-hpack-table :maximum-size maximum-table-size)
     :maximum-table-size maximum-table-size
     :huffman huffman
     :maximum-block-size maximum-block-size
     :maximum-header-list-size maximum-header-list-size
     :maximum-field-count maximum-field-count
     :maximum-string-length maximum-string-length)))

(defun %ensure-encoder (encoder)
  (unless (hpack-encoder-p encoder)
    (%hpack-block-error "Value must be an HPACK encoder." :hpack-encoder encoder))
  encoder)

(defun hpack-encoder-set-table-size (encoder maximum-table-size)
  (%ensure-encoder encoder)
  (%ensure-table-size maximum-table-size "Encoder maximum table size")
  (let ((old-size (hpack-encoder-maximum-table-size encoder)))
    (unless (= old-size maximum-table-size)
      (hpack-table-set-maximum-size (hpack-encoder-table encoder)
                                    maximum-table-size)
      (setf (hpack-encoder-maximum-table-size encoder) maximum-table-size
            (hpack-encoder-pending-minimum-table-size encoder)
            (min maximum-table-size
                 (or (hpack-encoder-pending-minimum-table-size encoder)
                     maximum-table-size))
            (hpack-encoder-pending-final-table-size encoder) maximum-table-size)))
  encoder)
