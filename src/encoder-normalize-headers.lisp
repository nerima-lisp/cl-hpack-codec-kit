(in-package #:hpack-codec)

(defun %hpack-normalize-headers (headers limit field-limit)
  (let ((normalized nil)
        (count 0)
        (size 0))
    (dolist (header (%hpack-header-sequence headers))
      (incf count)
      (when (> count field-limit)
        (%hpack-block-limit-error
         "The HPACK header field count exceeds its limit."
         :hpack-header-block
         field-limit))
      (let ((header (%hpack-normalize-header header)))
        (incf size (+ 32
                      (length (hpack-header-name header))
                      (length (hpack-header-value header))))
        (when (> size limit)
          (%hpack-block-limit-error
           "The HPACK header list exceeds its limit."
           :hpack-header-block
           limit))
        (push header normalized)))
    (nreverse normalized)))
