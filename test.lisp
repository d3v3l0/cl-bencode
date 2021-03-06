;;; -*- Mode: Lisp -*-

(defpackage #:bencode-test
  (:use #:cl #:bencode #:hu.dwim.stefil #:check-it)
  (:export #:test-all))

(in-package #:bencode-test)

(defsuite* test-all)

;;; Generated input.

(def-generator any-string ()
  (generator (map (lambda (x) (coerce x 'string))
                  (list (character)))))

(defun make-dict (keys values)
  (let ((dict (make-hash-table :test 'equal)))
    (loop for k in keys
          for v in values
          do (setf (gethash k dict) v))
    dict))

(def-generator input ()
  (generator (or (integer)
                 (any-string)
                 (list (input))
                 (map #'make-dict
                      (list (any-string))
                      (list (input))))))

(defun roundtrip-p (x)
  (equalp x (decode (encode x nil))))

(deftest roundtrip-test ()
  (let ((*binary-key-p* nil))
    (is (check-it (generator (input))
                  #'roundtrip-p))))

(def-generator binary-string ()
  (generator (map (lambda (x)
                    (make-array (length x)
                                :initial-contents x
                                :element-type '(unsigned-byte 8)))
                  (list (integer 0 255)))))

(defvar *binary-mark* "binary")

(defun binary-key-p (x)
  (let ((str (first x)))
    (search *binary-mark* str
            :start2 0
            :end2 (min (length *binary-mark*) (length str)))))

(def-generator binary-key ()
  (generator (map (lambda (x) (concatenate 'string "binary" x))
                  (string))))

(def-generator string-key ()
  (generator (guard (lambda (x)
                      (not (binary-key-p x)))
                    (string))))

(def-generator mixed-input ()
  (generator (or (integer)
                 (any-string)
                 (list (mixed-input))
                 (map #'make-dict
                      (list (any-string))
                      (list (mixed-input)))
                 (map #'make-dict
                      (list (binary-key))
                      (list (binary-string))))))

(deftest binary-roundtrip-test ()
  (let ((*binary-key-p* #'binary-key-p))
    (is (check-it (generator (mixed-input))
                  #'roundtrip-p))))

;;; Integers

(deftest decode-integer-test ()
  (dolist (case '(("i0e" 0)
		  ("i-1e" -1)
		  ("i23e" 23)))
    (destructuring-bind (input expected) case
      (is (= expected (decode input))))))

(deftest integer-rountrip-test ()
  (dolist (integer (list 0 1 -2 most-positive-fixnum most-negative-fixnum
			 (1+ most-positive-fixnum)
			 (1- most-negative-fixnum)))
    (is (= integer (decode (encode integer nil))))))

(deftest encode-unknown-type-error-test ()
  (signals error (encode 'symbol nil)))

(deftest decode-bad-integer-test ()
  (dolist (input '("i-0e" "i00e" "i01e" "i-02e" "i3.0e" "i0"))
    (signals error (decode input))))

;;; Strings

(defparameter *non-ascii-string* "räksmörgås½§")

(defparameter *encodings* '(:iso-8859-1 :utf-8 :utf-16 :utf-32)
  "Encodings ordered by the length of encoded latin code points.")

(deftest external-format-roundtrip-test ()
  (dolist (encoding *encodings*)
    (let ((string *non-ascii-string*))
      (is (string= string (decode (encode *non-ascii-string* nil
					  :external-format encoding)
				  :external-format encoding))))))

(deftest external-format-length-test ()
  (let ((encoded-lengths (mapcar #'(lambda (enc)
				     (length (encode *non-ascii-string* nil
						     :external-format enc)))
				 *encodings*)))
    (is (apply #'< encoded-lengths))))

(deftest decode-string-specializer-test ()
  (is (string= "foo" (decode "3:foo"))))

(deftest wrong-string-length-test ()
  (signals error (decode "3:ab")))

;;; Lists

(deftest list-roundtrip-test ()
  (dolist (list '(nil (1) (("a" 2)) ("c" (("d") 5 ()))))
    (is (equalp list (decode (encode list nil))))))

(deftest list-not-closed-test ()
  (signals error (decode "li0e")))

;;; Dictionaries

(deftest dict-roundtrip-test ()
  (dolist (dict (mapcar #'bencode::make-dictionary
			'(()
			  ("foo" "bar")
			  ("aa" 12 "ab" 34))))
    (is (equalp dict (decode (encode dict nil))))))

(deftest binary-dictionary-keys-test ()
  (flet ((decode (binary-key-p)
           (let ((bencode:*binary-key-p* binary-key-p))
             (decode "d4:infod6:binary3:abc6:string3:cdeee"))))
    (let ((none (decode (lambda (x) (declare (ignore x)) nil)))
          (some (decode (lambda (x) (equal x '("binary" "info")))))
          (all (decode (lambda (x) (equal "info" (cadr x))))))
      (is (typep (gethash "binary" (gethash "info" none))
                 'string))
      (is (typep (gethash "string" (gethash "info" none))
                 'string))
      (is (not (typep (gethash "binary" (gethash "info" some))
                      'string)))
      (is (typep (gethash "string" (gethash "info" some))
                 'string))
      (is (not (typep (gethash "binary" (gethash "info" all))
                      'string)))
      (is (not (typep (gethash "string" (gethash "info" all))
                      'string))))))

(deftest bad-dictionary-test ()
  (dolist (dict '("d3:fooe" 		; Missing value
		  "di0e0:e"		; Non-string key
		  "d1:a0:"		; Not closed with #\e
		  "d1:z0:1:a0:e"	; Keys not sorted
		  ))
    (signals error (decode dict))))
