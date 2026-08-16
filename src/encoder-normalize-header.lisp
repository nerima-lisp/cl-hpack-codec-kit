(in-package #:hpack-codec)

(defun %hpack-normalize-header (header)
  (cond
    ((hpack-header-p header)
     (make-hpack-header
      :name (hpack-header-name header)
      :value (hpack-header-value header)
      :representation (hpack-header-representation header)))
    ((consp header)
     (if (%hpack-proper-list-p header)
         (case (length header)
           (2 (make-hpack-header (first header) (second header)))
           (3 (make-hpack-header (first header) (second header) (third header)))
           (otherwise
            (%hpack-block-error
             "An HPACK header list must contain two or three elements."
             :hpack-header
             header)))
         (if (consp (cdr header))
             (%hpack-block-error
              "An HPACK header must be a proper list or a dotted pair."
              :hpack-header
              header)
             (make-hpack-header (car header) (cdr header)))))
    (t
     (%hpack-block-error
      "An HPACK header must be an HPACK header object or a pair."
      :hpack-header
      header))))
