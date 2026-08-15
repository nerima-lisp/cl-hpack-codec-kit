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
