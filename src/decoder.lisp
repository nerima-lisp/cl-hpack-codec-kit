(in-package #:hpack-codec)

(defun %hpack-decoding-error (message &optional detail)
  (error 'hpack-decoding-error
         :message message
         :operation :hpack-decode
         :detail detail))

(defun %hpack-decoder-table-entry (table index)
  (handler-case
      (hpack-table-lookup table index)
    (hpack-codec-error (condition)
      (%hpack-decoding-error "An HPACK table index is invalid." condition))))

(defun %hpack-read-literal* (octets position table prefix-bits representation
                              maximum-string-length maximum-header-bytes
                              current-header-list-size)
  (multiple-value-bind (name-index position)
      (handler-case
          (hpack-read-integer octets position prefix-bits)
        (hpack-codec-error (condition)
          (%hpack-decoding-error "An HPACK literal name index is invalid."
                                 condition)))
    (let ((remaining-header-bytes
            (- maximum-header-bytes current-header-list-size 32)))
      (when (minusp remaining-header-bytes)
        (%hpack-block-limit-error
         "The HPACK header list exceeds its limit."
         :hpack-header-block
         maximum-header-bytes))
      (let ((name nil))
        (if (zerop name-index)
            (multiple-value-bind (decoded-name next-position ignored-huffman)
                (hpack-read-string
                 octets position
                 :maximum-length
                 (min maximum-string-length remaining-header-bytes))
              (declare (ignore ignored-huffman))
              (setf name decoded-name
                    position next-position))
            (let ((entry (%hpack-decoder-table-entry table name-index)))
              (setf name (hpack-table-entry-name entry))))
        (let ((remaining-value-bytes
                (- remaining-header-bytes (length name))))
          (when (minusp remaining-value-bytes)
            (%hpack-block-limit-error
             "The HPACK header list exceeds its limit."
             :hpack-header-block
             maximum-header-bytes))
          (multiple-value-bind (value next-position)
              (hpack-read-string
               octets position
               :maximum-length
               (min maximum-string-length remaining-value-bytes))
            (values name value next-position representation)))))))

(defun %hpack-read-table-size-update (octets position)
  (handler-case
      (hpack-read-integer octets position 5)
    (hpack-codec-error (condition)
      (%hpack-decoding-error "An HPACK table size update is invalid."
                             condition))))

(defun %hpack-decode-indexed-field (octets position table)
  (multiple-value-bind (index next-position)
      (handler-case
          (hpack-read-integer octets position 7)
        (hpack-codec-error (condition)
          (%hpack-decoding-error "An HPACK indexed representation is invalid."
                                 condition)))
    (when (zerop index)
      (%hpack-decoding-error
       "The HPACK indexed representation has index zero."))
    (let ((entry (%hpack-decoder-table-entry table index)))
      (values
       (make-hpack-header
        :name (hpack-table-entry-name entry)
        :value (hpack-table-entry-value entry)
        :representation :indexed)
       next-position))))

(defun %hpack-decode-literal-field
    (octets position table prefix-bits representation insert-p
     maximum-string-length maximum-header-bytes header-list-size)
  (multiple-value-bind (name value next-position ignored-representation)
      (%hpack-read-literal* octets position table prefix-bits representation
                            maximum-string-length maximum-header-bytes
                            header-list-size)
    (declare (ignore ignored-representation))
    (when insert-p
      (hpack-table-insert table name value))
    (values (make-hpack-header
             :name name
             :value value
             :representation representation)
            next-position)))

(defun %hpack-decode-indexed-one (octets position table)
  (multiple-value-bind (header next-position)
      (%hpack-decode-indexed-field octets position table)
    (values :header header next-position)))

(defun %hpack-decode-table-size-one (octets position table decoder)
  (declare (ignore table))
  (multiple-value-bind (maximum-size next-position)
      (%hpack-read-table-size-update octets position)
    (when (> maximum-size (hpack-decoder-maximum-table-size decoder))
      (%hpack-decoding-error
       "An HPACK table size update exceeds the decoder limit."
       maximum-size))
    (values :table-size maximum-size next-position)))

(defun %hpack-decode-literal-one
    (octets position table decoder prefix-bits representation insert-p
     max-header-bytes header-list-size)
  (multiple-value-bind (header next-position)
      (%hpack-decode-literal-field
       octets position table prefix-bits representation insert-p
       (hpack-decoder-maximum-string-length decoder)
       max-header-bytes header-list-size)
    (values :header header next-position)))

(defun %hpack-decode-one
    (octets position table decoder max-header-bytes header-list-size)
  (let ((first (aref octets position)))
    (cond
      ((logbitp 7 first)
       (%hpack-decode-indexed-one octets position table))
      ((= (logand first #xe0) #x20)
       (%hpack-decode-table-size-one octets position table decoder))
      ((= (logand first #xc0) #x40)
       (%hpack-decode-literal-one
        octets position table decoder 6 :incremental-indexing t
        max-header-bytes header-list-size))
      ((= (logand first #xf0) #x10)
       (%hpack-decode-literal-one
        octets position table decoder 4 :never-indexed nil
        max-header-bytes header-list-size))
      (t
       (%hpack-decode-literal-one
        octets position table decoder 4 :without-indexing nil
        max-header-bytes header-list-size)))))

(defun %hpack-decode-block-step
    (decoder octets table position headers header-seen-p size-updates
     header-list-size field-count max-fields max-header-bytes
     validate-header-names)
  (loop with current-position = position
        with current-headers = headers
        with current-header-seen-p = header-seen-p
        with current-size-updates = size-updates
        with current-header-list-size = header-list-size
        with current-field-count = field-count
        while (< current-position (length octets))
        do (multiple-value-bind (kind object next-position)
               (%hpack-decode-one octets current-position table decoder
                                  max-header-bytes current-header-list-size)
             (setf current-position next-position)
             (if (eq kind :table-size)
                 (progn
                   (when current-header-seen-p
                     (%hpack-decoding-error
                      "A dynamic table size update must precede header fields."))
                   (incf current-size-updates)
                   (when (> current-size-updates 2)
                     (%hpack-decoding-error
                      "An HPACK block contains too many table size updates."))
                   (hpack-table-set-maximum-size table object)
                   (setf current-header-seen-p nil))
                 (progn
                   (when (and validate-header-names
                              (not (hpack-valid-header-name-p
                                    (hpack-header-name object))))
                     (%hpack-decoding-error
                      "An HPACK header name is invalid for HTTP/2."
                      (hpack-header-name object)))
                   (multiple-value-bind (new-field-count new-header-list-size)
                       (%hpack-account-decoded-header
                        object current-field-count current-header-list-size
                        max-fields max-header-bytes)
                     (setf current-headers (cons object current-headers)
                           current-header-seen-p t
                           current-field-count new-field-count
                           current-header-list-size new-header-list-size)))))
        finally (return (values (nreverse current-headers) table))))

(defun %hpack-decode-block
    (decoder octets max-fields max-header-bytes validate-header-names)
  (%hpack-ensure-octets octets :hpack-decode)
  (when (> (length octets) (hpack-decoder-maximum-block-size decoder))
    (%hpack-block-limit-error
     "The HPACK header block exceeds its limit."
     :hpack-header-block
     (hpack-decoder-maximum-block-size decoder)))
  (%hpack-decode-block-step
   decoder octets
   (hpack-table-copy (hpack-decoder-table decoder))
   0 nil nil 0 0 0
   max-fields max-header-bytes validate-header-names))

(defun hpack-decode-header-block (decoder octets &rest arguments)
  "Decode OCTETS using DECODER and return an ordered list of HPACK headers.

MAX-FIELDS and MAX-HEADER-BYTES may tighten the decoder limits for this call.
:VALIDATE-HEADER-NAMES can enable validation for this call, but cannot disable
validation configured on DECODER."
  (%hpack-check-keywords
   arguments '(:max-fields :max-header-bytes :validate-header-names)
   :hpack-decode)
  (%ensure-decoder decoder)
  (let* ((call-max-fields
           (%hpack-ensure-limit
            (getf arguments :max-fields
                  (hpack-decoder-maximum-field-count decoder))
            :max-fields))
         (call-max-header-bytes
           (%hpack-ensure-limit
            (getf arguments :max-header-bytes
                  (hpack-decoder-maximum-header-list-size decoder))
            :max-header-bytes))
         (call-validate-header-names
           (getf arguments :validate-header-names nil))
         (max-fields
           (min call-max-fields
                (hpack-decoder-maximum-field-count decoder)))
         (max-header-bytes
           (min call-max-header-bytes
                (hpack-decoder-maximum-header-list-size decoder)))
         (validate-header-names
           (or call-validate-header-names
               (hpack-decoder-validate-header-names decoder))))
    (unless (member call-validate-header-names '(nil t) :test #'eq)
      (%hpack-block-error
       "The HPACK header-name validation option must be boolean."
       :hpack-decode
       call-validate-header-names))
    (handler-case
        (multiple-value-bind (headers table)
            (%hpack-decode-block decoder octets max-fields max-header-bytes
                                 validate-header-names)
          (setf (hpack-decoder-table decoder) table)
          headers)
      (hpack-limit-error (condition)
        (error condition))
      (hpack-decoding-error (condition)
        (error condition))
      (hpack-codec-error (condition)
        (error 'hpack-decoding-error
               :message "The HPACK header block is malformed."
               :operation :hpack-decode
               :detail condition)))))

(defun hpack-decoder-buffered-size (decoder)
  "Return the number of octets accumulated for the next header block."
  (%ensure-decoder decoder)
  (length (hpack-decoder-pending-octets decoder)))

(defun hpack-decoder-feed (decoder octets)
  "Append an octet fragment and return the accumulated header-block size.

The decoder does not update its dynamic table until HPACK-DECODER-FINISH
successfully decodes the accumulated block."
  (%ensure-decoder decoder)
  (%hpack-ensure-octets octets :hpack-decoder-feed)
  (let ((new-size (+ (length (hpack-decoder-pending-octets decoder))
                     (length octets))))
    (when (> new-size (hpack-decoder-maximum-block-size decoder))
      (%hpack-block-limit-error
       "The accumulated HPACK header block exceeds its limit."
       :hpack-decoder-feed
       (hpack-decoder-maximum-block-size decoder)))
    (setf (hpack-decoder-pending-octets decoder)
          (%hpack-append-octets
           (list (hpack-decoder-pending-octets decoder)
                 octets)))
    new-size))

(defun hpack-decoder-finish (decoder &rest arguments)
  "Decode buffered fragments, clearing them only after success.

Accepts the same call-specific limits and validation option as
HPACK-DECODE-HEADER-BLOCK. Failed decoding leaves the fragments buffered."
  (%ensure-decoder decoder)
  (let ((headers (apply #'hpack-decode-header-block
                        decoder
                        (hpack-decoder-pending-octets decoder)
                        arguments)))
    (setf (hpack-decoder-pending-octets decoder)
          (make-array 0 :element-type '(unsigned-byte 8)))
    headers))

(defun hpack-decoder-abort (decoder)
  "Discard the accumulated fragments without changing decoder table state."
  (%ensure-decoder decoder)
  (setf (hpack-decoder-pending-octets decoder)
        (make-array 0 :element-type '(unsigned-byte 8)))
  decoder)
