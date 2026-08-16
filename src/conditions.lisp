(in-package #:hpack-codec)

;; The slot shape (message, operation, detail) mirrors the protocol-error
;; conditions used by the HTTP libraries that consume this codec, so a caller
;; can translate one into the other without losing the diagnostic payload.
(define-condition hpack-codec-error (error)
  ((message :initarg :message :reader hpack-codec-error-message)
   (operation :initarg :operation :initform nil :reader hpack-codec-error-operation)
   (detail :initarg :detail :initform nil :reader hpack-codec-error-detail))
  (:report (lambda (condition stream)
             (format stream "~A" (hpack-codec-error-message condition)))))

(define-condition hpack-decoding-error (hpack-codec-error) ())

(define-condition hpack-limit-error (hpack-codec-error) ())

(defun %hpack-ensure-octets (value operation)
  (unless (vectorp value)
    (error 'hpack-codec-error
           :message "HPACK octets must be a vector."
           :operation operation
           :detail value))
  (loop for octet across value
        unless (and (integerp octet) (<= 0 octet #xff))
          do (error 'hpack-codec-error
                    :message "HPACK octets must contain bytes."
                    :operation operation
                    :detail octet))
  value)

(defun %hpack-ensure-limit (value name)
  (unless (and (integerp value) (>= value 0))
    (error 'hpack-codec-error
           :message "An HPACK limit must be a non-negative integer."
           :operation :hpack
           :detail (list name value)))
  value)
