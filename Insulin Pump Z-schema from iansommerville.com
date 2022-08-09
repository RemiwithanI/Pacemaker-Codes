#Source: https://iansommerville.com/software-engineering-book/case-studies/insulin-pump/

INSULIN_PUMP_STATE---

  //Input device definition

  switch?: (off, manual, auto)
  ManualDeliveryButton?: N                                      ## natural number N
  Reading?: N
  HardwareTest?: (OK, batterylow, pumpfail, sensorfail, deliveryfail)
  InsulinReservoir?: (present, notpresent)
  Needle?: (present, notpresent)
  clock?: TIME

  //Output device definition

  alarm! = (on, off)
  display1!, P string                                         ## irrational number P
  display2!: string
  clock!: TIME
  dose!: N

  // State variables used for dose computation

  status: (running, warning, error)
  r0, r1, r2: N                                             ## natural number N
  capacity, insulin_available : N
  max_daily_dose, max_single_dose, minimum_dose: N
  safemin, safemax: N
  CompDose, cumulative_dose: N

---

  r2 = Reading?
  dose! ≤ insulin_available
  insulin_available ≤ capacity
  // The cumulative dose of insulin delivered is set to zero once every 24 hours
  clock? = 000000 ⇒ cumulative_dose = 0
  // If the cumulative dose exceeds the limit then operation is suspended

  cumulative_dose >= max_daily_dose ⋀ status = error ⋀ display1! =
“Daily dose exceeded”

  // Pump configuration parameters
  capacity = 100
  safemin = 6
  safemax = 14
  max_daily_dose = 25
  max_single_dose = 4
  minimum_dose = 1
  
display2! = nat_to_string (dose!)
  clock! = clock?
  
---

RUN ---

  ∆INSULIN_PUMP_STATE

  switch? = auto
  status = running ∨ status = warning
  insulin_available ≥ max_single_dose
  cumulative_dose < max_daily_dose

  (SUGAR_LOW ∨ SUGAR_OK ∨ SUGAR_HIGH)
  // If the computed insulin dose is zero, don’t deliver any insulin
            CompDose = 0 ⇒ dose! = 0
  ∨
  // The maximum daily dose would be exceeded if the computed dose was delivered
          CompDose + cumulative_dose > max_daily_dose ⇒ alarm! = on
          ⋀ status’ = warning ⋀ dose! = max_daily_dose – umulative_dose
  ∨
  // The normal situation. If maximum single dose is not exceeded then deliver computed
dose
         CompDose + cumulative_dose < max_daily_dose ⇒ 
          (CompDose ≤ max_single_dose ⇒ dose! = CompDose
         ∨
  // The single dose computed is too high. Restrict the dose delivered to the maximum single
dose
            CompDose > max_single_dose ⇒ dose! = max_single_dose
            )
  insulin_available’ = insulin_available – dose!
  cumulative_dose’ = cumulative_dose + dose!

  insulin_available ≤ max_single_dose * 4 ⇒ status’ = warning ⋀ display1! =
  display1! ∪ “Insulin low”

  r1’ = r2
  r0’ = r1

---

MANUAL---

  ∆INSULIN_PUMP_STATE

  switch? = manual
  display1! = "Manual override"
  dose! = ManualDeliveryButton?
  cumulative_dose' = cumulative_dose + dose!
  insulin_available' = insulin_available - dose!

---

SUGAR_LOW ---
  
  r2 < safemin
  CompDose = 0
  alarm! = on
  status’ = warning
  display1! = display1! ∪ “Sugar low”

---

SUGAR_OK---

  r2 ≥ safemin ⋀ r2 ≤ safemax
  // sugar level stable or falling
  r2 ≤ r1 ⇒ CompDose = 0
  ∨
  // sugar level increasing but rate of increase falling
  r2 > r1 ⋀ (r2-r1) < (r1-r0) ⇒ CompDose = 0
  ∨
  // sugar level increasing and rate of increase increasing compute dose
  // a minimum dose must be delivered if rounded to zero
  r2 > r1 ⋀ (r2-r1) ≥ (r1-r0) ⋀ (round ((r2-r1)/4) = 0) ⇒
                                   CompDose = minimum_dose
  ∨
  r2 > r1 ⋀ (r2-r1) ≥ (r1-r0) ⋀ (round ((r2-r1)/4) > 0) ⇒
                                   CompDose = round ((r2-r1)/4)

---

SUGAR_HIGH---

  r2 > safemax
  // sugar level increasing. Round down if below 1 unit.
  r2 > r1 ⋀ (round ((r2-r1)/4) = 0) ⇒ CompDose = minimum_dose
  ∨
  r2 > r1 ⋀ (round ((r2-r1)/4) = 0) ⇒ CompDose = round ((r2-r1)/4)
  ∨
  // sugar level stable
  r2 = r1 ⇒ CompDose = minimum_dose
  ∨
  // sugar level falling and rate of decrease increasing
  r2 < r1 ⋀ (r2-r1) ≤ (r1-r0) ⇒ CompDose = 0
  ∨
  //sugar level falling and rate of decrease decreasing
  r2 < r1 ⋀ (r2-r1) ≤ (r1-r0) ⇒ CompDose = minimum_dose

---

STARTUP---

    ∆INSULIN_PUMP_STATE
  switch? = off ⋀ switch?' = auto
  dose! = 0
  r0' = safemin
  r1' = safemax
  TEST
  
---

RESET---

              ∆INSULIN_PUMP_STATE
  InsulinReservoir? = notpresent and InsulinReservoir' = present
  insulin_available = capacity
  insulinlevel' = OK
  TEST

---

TEST---

  ∆INSULIN_PUMP_STATE

  (HardwareTest? = OK ⋀ Needle? = present ⋀ InsulinReservoir? = present ⇒
             status’ = running ⋀ alarm! = off ⋀ display1!= “” )
  ∨(
        status’ = error
        alarm! = on
        (
            Needle? = notpresent ⇒ display1! = display1! ∪ “No needle unit” ∨
            ( InsulinReservoir? = notpresent ∨ insulin_available < max_single_dose)
                              ⇒ display1! = display1! ∪ “No insulin” ∨ 
            HardwareTest? = batterylow ⇒ display1! = display1! ∪ ”Battery low” ∨
            HardwareTest? = pumpfail ⇒ display1! = display1! ∪ ”Pump failure” ∨
            HardwareTest? = sensorfail ⇒ display1! = display1! ∪ ”Sensor failure” ∨
            HardwareTest? = deliveryfail ⇒ display1! = display1! ∪ ”Needle failure” ∨
        )
  )

---


