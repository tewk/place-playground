#lang scheme
(require "places.ss")
(require tests/eli-tester)

;(require errortrace)
;(instrumenting-enabled #t)

(define p1 (create-place "echo.ss" "echo"))
(define p2 (create-place "echo.ss" "echo"))
(define ch1 (place-ch p1))
(define ch2 (place-ch p2))

(for ([x  (list ch1 ch2)]) (test (send/recv x "BOZO") => "BOZO"))
(for ([x  (list ch1 ch2)]) (test (send/recv x "BODO") => "BODO"))

(let ((nch (make-place-channel)))
  (send ch1 nch)
  (test (send/recv nch "BOOO") => "BOOO"))


;(sleep 2)
(kill-place p1)
(kill-place p2)
;(sleep 2)
(exit 0)




