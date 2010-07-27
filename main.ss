#lang racket
(require "places.ss")
(require tests/eli-tester)

;(require errortrace)
;(instrumenting-enabled #t)

(define p1 (place "echo.ss" "echo"))
(define p2 (place "echo.ss" "echo"))

(for ([x  (list p1 p2)]) (test (place-channel-send/recv x "BOZO") => "BOZO"))
(for ([x  (list p1 p2)]) (test (place-channel-send/recv x "BODO") => "BODO"))

(let ((nch (place-channel)))
  (place-channel-send p1 nch)
  (test (place-channel-send/recv nch "BOOO") => "BOOO"))


;(sleep 2)
(place-kill p1)
(place-kill p2)
;(sleep 2)
(exit 0)




