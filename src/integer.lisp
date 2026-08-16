(in-package #:hpack-codec)

(defun hpack-read-integer (octets position prefix-bits &key (maximum #xffffffff))
  "Decode an RFC 7541 prefixed integer and return its value and next position."
  (%hpack-ensure-octets octets :hpack-integer)
  (%hpack-ensure-limit maximum :integer-maximum)
  (unless (and (integerp position)
               (>= position 0)
               (integerp prefix-bits)
               (<= 1 prefix-bits 8)
               (< position (length octets)))
    (error 'hpack-codec-error
           :message "An HPACK integer is truncated or has an invalid prefix."
           :operation :hpack
           :detail position))
  (let* ((mask (1- (ash 1 prefix-bits)))
         (first (aref octets position))
         (value (logand first mask))
         (position (1+ position)))
       (if (< value mask)
           (if (<= value maximum)
               (values value position)
               (error 'hpack-codec-error
                      :message "An HPACK integer is too large."
                      :operation :hpack
                      :detail value))
           (progn
             (when (> mask maximum)
               (error 'hpack-codec-error
                      :message "An HPACK integer is too large."
                      :operation :hpack
                      :detail value))
             (let ((shift 0)
                   (continuation-count 0)
                   (maximum-continuations
                     (ceiling (max 1 (integer-length maximum)) 7)))
               (loop
                 (when (>= continuation-count maximum-continuations)
                   (error 'hpack-codec-error
                          :message "An HPACK integer has too many continuation octets."
                          :operation :hpack
                          :detail position))
                 (when (>= position (length octets))
                   (error 'hpack-codec-error
                          :message "An HPACK integer continuation is truncated."
                          :operation :hpack
                          :detail position))
                 (let ((octet (aref octets position)))
                   (incf position)
                   (incf continuation-count)
                   (let ((increment (ash (logand octet #x7f) shift)))
                     (when (> increment (- maximum value))
                       (error 'hpack-codec-error
                              :message "An HPACK integer is too large."
                              :operation :hpack
                              :detail value))
                     (incf value increment))
                   (if (zerop (logand octet #x80))
                       (return (values value position))
                       (incf shift 7)))))))))

(defun hpack-encode-integer (value prefix-bits prefix &key (maximum #xffffffff))
  "Encode VALUE as an RFC 7541 prefixed integer into a fresh octet vector."
  (%hpack-ensure-limit maximum :integer-maximum)
  (unless (and (integerp value) (>= value 0)
               (<= value maximum)
               (integerp prefix-bits)
               (<= 1 prefix-bits 8)
               (integerp prefix) (<= 0 prefix #xff))
    (error 'hpack-codec-error
           :message "Cannot encode an invalid HPACK integer."
           :operation :hpack
           :detail value))
  (let* ((mask (1- (ash 1 prefix-bits)))
         (prefix (logand prefix #xff)))
    (when (not (zerop (logand prefix mask)))
      (error 'hpack-codec-error
             :message "HPACK integer prefix flags overlap the value field."
             :operation :hpack
             :detail prefix))
    (if (< value mask)
        (let ((result (make-array 1 :element-type '(unsigned-byte 8))))
          (setf (aref result 0) (logior prefix value))
          result)
        (let ((result (make-array 1 :element-type '(unsigned-byte 8)
                                  :adjustable t :fill-pointer 1)))
          (setf (aref result 0) (logior prefix mask))
          (decf value mask)
          (loop while (>= value 128)
                do (vector-push-extend (logior #x80 (logand value #x7f)) result)
                   (setf value (ash value -7)))
          (vector-push-extend value result)
          (let ((copy (make-array (length result)
                                  :element-type '(unsigned-byte 8))))
            (replace copy result)
            copy)))))
