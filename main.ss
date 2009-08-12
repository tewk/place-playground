#lang scheme

(require "places.ss")
(require tests/eli-tester)

(define p1 (create-place "echo.ss" "echo"))
(define p2 (create-place "echo.ss" "echo"))

(define (gotit x)
  (printf "GOTIT #~a#~n" x))
(define ch1 (place-ch p1))
(define ch2 (place-ch p2))


(map (λ (x) (test (send/recv x "BOZO") => "BOZO")) (list ch1 ch2))
(map (λ (x) (test (send/recv x "BODO") => "BODO")) (list ch1 ch2))

(let ((nch (make-place-channel)))
  (send ch1 nch)
  (test (send/recv nch "BOOO") => "BOOO"))


;(sleep 2)
(kill-place p1)
(kill-place p2)
;(sleep 2)
(exit 0)
;(connect-places p1 p2)




