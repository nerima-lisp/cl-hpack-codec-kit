(in-package #:hpack-codec)

(defparameter *hpack-default-maximum-block-size* (* 16 1024 1024))
(defparameter *hpack-default-maximum-header-list-size* (* 16 1024 1024))
(defparameter *hpack-default-maximum-field-count* 65536)
(defparameter *hpack-default-maximum-string-length* (* 16 1024 1024))

(defun %hpack-block-error (message operation &optional detail)
  (error 'hpack-codec-error
         :message message
         :operation operation
         :detail detail))

(defun %hpack-block-limit-error (message operation detail)
  (error 'hpack-limit-error
         :message message
         :operation operation
         :detail detail))

(defun %hpack-copy-octets (octets)
  (%hpack-ensure-octets octets :hpack)
  (let ((copy (make-array (length octets)
                          :element-type '(unsigned-byte 8))))
    (replace copy octets)
    copy))

(defun %hpack-coerce-octets (value operation)
  (cond
    ((stringp value)
     (let ((result (make-array (length value)
                               :element-type '(unsigned-byte 8))))
       (loop for character across value
             for index from 0
             for code = (char-code character)
             do (unless (<= 0 code #xff)
                  (%hpack-block-error
                   "HPACK strings must contain octets."
                   operation
                   character))
                (setf (aref result index) code))
       result))
    ((vectorp value)
     (%hpack-copy-octets value))
    (t
     (%hpack-block-error
      "HPACK fields must be strings or octet vectors."
      operation
      value))))

(defun %hpack-normalize-representation (representation)
  (let ((representation (or representation :auto)))
    (unless (member representation
                    '(:auto :indexed :incremental-indexing
                      :without-indexing :never-indexed)
                    :test #'eq)
      (%hpack-block-error
       "Unknown HPACK header representation."
       :hpack-header
       representation))
    representation))

(defun %hpack-check-keywords (arguments allowed operation)
  (let ((remaining arguments)
        (seen nil))
    (unless (evenp (length remaining))
      (%hpack-block-error "Keyword arguments are incomplete." operation arguments))
    (loop while remaining
          do (let ((key (pop remaining)))
               (unless (and (keywordp key) (member key allowed :test #'eq))
                 (%hpack-block-error "Unknown keyword argument." operation key))
               (when (member key seen :test #'eq)
                 (%hpack-block-error "A keyword argument was supplied more than once."
                                     operation
                                     key))
               (push key seen)
               (pop remaining))))
  arguments)

(defun make-hpack-header (&rest arguments)
  (let ((name nil)
        (value nil)
        (representation :auto))
    (if (and arguments (keywordp (first arguments)))
        (progn
          (%hpack-check-keywords arguments '(:name :value :representation)
                                 :hpack-header)
          (setf name (getf arguments :name)
                value (getf arguments :value)
                representation (getf arguments :representation :auto)))
        (progn
          (unless (<= 2 (length arguments) 3)
            (%hpack-block-error
             "A positional HPACK header requires two or three arguments."
             :hpack-header
             arguments))
          (setf name (first arguments)
                value (second arguments)
                representation (or (third arguments) :auto))))
    (unless (and name value)
      (%hpack-block-error
       "An HPACK header requires a name and value."
       :hpack-header
       arguments))
    (%make-hpack-header
     (%hpack-coerce-octets name :hpack-header)
     (%hpack-coerce-octets value :hpack-header)
     (%hpack-normalize-representation representation))))

(defun %hpack-append-octets (vectors)
  (let ((result (make-array (loop for vector in vectors sum (length vector))
                            :element-type '(unsigned-byte 8)))
        (position 0))
    (dolist (vector vectors result)
      (replace result vector :start1 position)
      (incf position (length vector)))))

(defun %hpack-ensure-huffman-option (huffman)
  (unless (member huffman '(nil t :auto) :test #'eq)
    (%hpack-block-error
     "The HPACK Huffman option is invalid."
     :hpack-string
     huffman))
  huffman)

(defun hpack-encode-string
    (octets &key (huffman :auto)
                 (maximum-length *hpack-default-maximum-string-length*))
  "Encode an HPACK string literal, selecting raw or Huffman payload encoding."
  (let* ((octets (%hpack-coerce-octets octets :hpack-string))
         (maximum-length (%hpack-ensure-limit maximum-length :string-length))
         (huffman (%hpack-ensure-huffman-option huffman)))
    (when (> (length octets) maximum-length)
      (%hpack-block-limit-error
       "The HPACK string exceeds its length limit."
       :hpack-string
       maximum-length))
    (let* ((encoded-huffman
             (when (member huffman '(t :auto) :test #'eq)
               (hpack-huffman-encode octets
                                     :maximum-length maximum-length)))
           (use-huffman (case huffman
                          ((nil) nil)
                          ((t) t)
                          ((:auto) (< (length encoded-huffman) (length octets)))))
           (payload (if use-huffman encoded-huffman octets))
           (prefix (if use-huffman #x80 0))
           (length-octets (hpack-encode-integer (length payload) 7 prefix)))
      (%hpack-append-octets (list length-octets payload)))))

(defun hpack-read-string
    (octets position
            &key (maximum-length *hpack-default-maximum-string-length*))
  "Read an HPACK string literal, returning octets, next position, and H flag."
  (%hpack-ensure-octets octets :hpack-string)
  (let ((maximum-length (%hpack-ensure-limit maximum-length :string-length)))
    (unless (and (integerp position)
                 (>= position 0)
                 (< position (length octets)))
      (error 'hpack-decoding-error
             :message "An HPACK string is truncated or has an invalid position."
             :operation :hpack-string
             :detail position))
    (let ((first (aref octets position)))
      (multiple-value-bind (payload-length payload-position)
          (handler-case
              (hpack-read-integer octets position 7)
            (hpack-codec-error (condition)
              (error 'hpack-decoding-error
                     :message "An HPACK string length is invalid."
                     :operation :hpack-string
                     :detail condition)))
        (when (> payload-length (- (length octets) payload-position))
          (error 'hpack-decoding-error
                 :message "An HPACK string payload is truncated."
                 :operation :hpack-string
                 :detail position))
        (let* ((huffman (logbitp 7 first))
               (value
                 (if huffman
                     (handler-case
                         (%hpack-huffman-decode-range
                          octets payload-position
                          (+ payload-position payload-length)
                          maximum-length)
                       (hpack-limit-error (condition)
                         (error condition))
                       (hpack-codec-error (condition)
                         (error 'hpack-decoding-error
                                :message "An HPACK Huffman string is invalid."
                                :operation :hpack-string
                                :detail condition)))
                     (progn
                       (when (> payload-length maximum-length)
                         (%hpack-block-limit-error
                          "The HPACK string exceeds its length limit."
                          :hpack-string
                          maximum-length))
                       (let ((value
                               (make-array payload-length
                                           :element-type '(unsigned-byte 8))))
                         (replace value octets
                                  :start2 payload-position
                                  :end2 (+ payload-position payload-length))
                         value)))))
          (values value (+ payload-position payload-length) huffman))))))
(defun %hpack-header-name-character-p (code)
  (or (<= (char-code #\0) code (char-code #\9))
      (<= (char-code #\a) code (char-code #\z))
      (member code '(33 35 36 37 38 39 42 43 45 46 94 95 96 124 126)
              :test #'=)))

(defun hpack-valid-header-name-p (name)
  "Return whether NAME is a lowercase ASCII token with an optional leading colon.

This checks syntax only; it does not validate pseudo-header names or ordering."
  (and (or (stringp name) (vectorp name))
       (plusp (length name))
       (let* ((first (if (stringp name)
                         (char-code (char name 0))
                         (aref name 0)))
              (valid-first-p (and (integerp first) (<= 0 first 127)))
              (start (if (and valid-first-p
                              (= first (char-code #\:)))
                         1
                         0))
              (length (length name)))
         (and valid-first-p
              (< start length)
              (loop for index from start below length
                    for code = (if (stringp name)
                                   (char-code (char name index))
                                   (aref name index))
                    always (and (integerp code)
                                (<= 0 code 127)
                                (%hpack-header-name-character-p code)))))))
