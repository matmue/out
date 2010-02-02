MODULE CONTROL_FUNCTIONS
! Routines for evaluating control functions
USE PRECISION_PARAMETERS
USE CONTROL_VARIABLES
USE GLOBAL_CONSTANTS, ONLY : NMESHES

IMPLICIT NONE

CHARACTER(255), PARAMETER :: ctrlid='$Id$'
CHARACTER(255), PARAMETER :: ctrlrev='$Revision$'
CHARACTER(255), PARAMETER :: ctrldate='$Date$'

CONTAINS

SUBROUTINE UPDATE_CONTROLS(T)
! Update the value of all sensing DEVICEs and associated output quantities
REAL(EB), INTENT(IN) :: T(NMESHES)
INTEGER :: NC
 
CONTROL_LOOP_1: DO NC=1,N_CTRL
   IF (CONTROL(NC)%LATCH .AND. (CONTROL(NC)%INITIAL_STATE .NEQV. CONTROL(NC)%CURRENT_STATE)) THEN
      CONTROL(NC)%UPDATED = .TRUE.
      CONTROL(NC)%PRIOR_STATE = CONTROL(NC)%CURRENT_STATE
   ELSE
      CONTROL(NC)%UPDATED = .FALSE.
   ENDIF
END DO CONTROL_LOOP_1
CONTROL_LOOP_2: DO NC=1,N_CTRL
   IF (CONTROL(NC)%UPDATED) CYCLE CONTROL_LOOP_2
   CALL EVALUATE_CONTROL(T,NC)
END DO CONTROL_LOOP_2
   
END SUBROUTINE UPDATE_CONTROLS

RECURSIVE SUBROUTINE EVALUATE_CONTROL(T,ID)
USE DEVICE_VARIABLES
USE MATH_FUNCTIONS, ONLY:EVALUATE_RAMP
USE GLOBAL_CONSTANTS, ONLY : PROCESS_STOP_STATUS,USER_STOP,CORE_CLOCK
! Update the value of all sensing DEVICEs and associated output quantities
REAL(EB), INTENT(IN) :: T(NMESHES)
REAL(EB) :: RAMP_VALUE,T_CHANGE,RAMP_INPUT
INTEGER :: NC,COUNTER
INTEGER, INTENT(IN) :: ID
TYPE(CONTROL_TYPE), POINTER :: CF=>NULL()
TYPE(DEVICE_TYPE), POINTER :: DV=>NULL()
LOGICAL :: STATE1, STATE2

CF => CONTROL(ID)
CF%PRIOR_STATE = CF%CURRENT_STATE
T_CHANGE = -1000000._EB
STATE2 = .FALSE.
CONTROL_SELECT: SELECT CASE (CF%CONTROL_INDEX)
   CASE (AND_GATE)
      DO NC = 1, CF%N_INPUTS
         SELECT CASE (CF%INPUT_TYPE(NC))
            CASE (DEVICE_INPUT)
               DV => DEVICE(CF%INPUT(NC))
               IF (T(DV%MESH) >T_CHANGE) THEN
                  CF%MESH = DV%MESH
                  T_CHANGE = T(DV%MESH)
               ENDIF
               STATE1 = DV%CURRENT_STATE       
            CASE (CONTROL_INPUT)
               IF (.NOT. CONTROL(CF%INPUT(NC))%UPDATED) CALL EVALUATE_CONTROL(T,CF%INPUT(NC)) 
               STATE1 = CONTROL(CF%INPUT(NC))%CURRENT_STATE
               IF (T(CONTROL(CF%INPUT(NC))%MESH) > T_CHANGE) THEN
                  CF%MESH=CONTROL(CF%INPUT(NC))%MESH
                  T_CHANGE = T(CONTROL(CF%INPUT(NC))%MESH) 
               ENDIF
         END SELECT
         IF (NC==1) THEN
            STATE2 = STATE1
         ELSE
            STATE2 = STATE1 .AND. STATE2
         ENDIF
      ENDDO

  CASE (OR_GATE)
      DO NC = 1, CF%N_INPUTS
         SELECT CASE (CF%INPUT_TYPE(NC))
            CASE (DEVICE_INPUT)
               DV => DEVICE(CF%INPUT(NC))
               IF (T(DV%MESH) >T_CHANGE) THEN
                  CF%MESH = DV%MESH
                  T_CHANGE = T(DV%MESH)
               ENDIF
               STATE1 = DV%CURRENT_STATE
            CASE (CONTROL_INPUT)
               IF (.NOT. CONTROL(CF%INPUT(NC))%UPDATED) CALL EVALUATE_CONTROL(T,CF%INPUT(NC))
               STATE1 = CONTROL(CF%INPUT(NC))%CURRENT_STATE
               IF (T(CONTROL(CF%INPUT(NC))%MESH) > T_CHANGE) THEN
                  CF%MESH=CONTROL(CF%INPUT(NC))%MESH
                  T_CHANGE = T(CONTROL(CF%INPUT(NC))%MESH) 
               ENDIF
         END SELECT
         IF (NC==1) THEN
            STATE2 = STATE1
         ELSE
            STATE2 = STATE1 .OR. STATE2
         ENDIF
      ENDDO

   CASE (XOR_GATE)
      COUNTER = 0
      DO NC = 1, CF%N_INPUTS
         SELECT CASE (CF%INPUT_TYPE(NC))
            CASE (DEVICE_INPUT)
               DV => DEVICE(CF%INPUT(NC))
               IF (DV%CURRENT_STATE) THEN
                  COUNTER = COUNTER + 1
                  IF (T(DV%MESH) >T_CHANGE) THEN
                     CF%MESH = DV%MESH
                     T_CHANGE = T(DV%MESH)
                  ENDIF
               ENDIF
            CASE (CONTROL_INPUT)
               IF (.NOT. CONTROL(CF%INPUT(NC))%UPDATED) CALL EVALUATE_CONTROL(T,CF%INPUT(NC))
               IF (CONTROL(CF%INPUT(NC))%CURRENT_STATE) THEN
                  COUNTER = COUNTER + 1
                  IF (T(CONTROL(CF%INPUT(NC))%MESH) > T_CHANGE) THEN
                     CF%MESH=CONTROL(CF%INPUT(NC))%MESH
                     T_CHANGE = T(CONTROL(CF%INPUT(NC))%MESH) 
                  ENDIF
               ENDIF
         END SELECT
      ENDDO
      IF (COUNTER==CF%N) STATE2 = .TRUE.
   CASE (X_OF_N_GATE)
      COUNTER = 0
      DO NC = 1, CF%N_INPUTS
         SELECT CASE (CF%INPUT_TYPE(NC))
            CASE (DEVICE_INPUT)
               DV => DEVICE(CF%INPUT(NC))
               IF (DV%CURRENT_STATE) THEN
                  COUNTER = COUNTER + 1
                  IF (T(DV%MESH) >T_CHANGE) THEN
                     CF%MESH = DV%MESH
                     T_CHANGE = T(DV%MESH)
                  ENDIF              
               ENDIF
            CASE (CONTROL_INPUT)
               IF (.NOT. CONTROL(CF%INPUT(NC))%UPDATED) CALL EVALUATE_CONTROL(T,CF%INPUT(NC))
               IF (CONTROL(CF%INPUT(NC))%CURRENT_STATE) THEN
                  COUNTER = COUNTER + 1
                  IF (T(CONTROL(CF%INPUT(NC))%MESH) > T_CHANGE) THEN
                     CF%MESH=CONTROL(CF%INPUT(NC))%MESH
                     T_CHANGE = T(CONTROL(CF%INPUT(NC))%MESH) 
                  ENDIF
               ENDIF
         END SELECT
      ENDDO
      IF (COUNTER>=CF%N) STATE2 = .TRUE.

   CASE (DEADBAND)
       DV => DEVICE(CF%INPUT(1))
       T_CHANGE = T(DV%MESH)
       CF%MESH = DV%MESH
       IF (CF%ON_BOUND > 0) THEN
          IF (DV%INSTANT_VALUE > CF%SETPOINT(2) .AND. (CF%CURRENT_STATE .EQV. CF%INITIAL_STATE)) THEN
             STATE2 = .TRUE.
          ELSEIF(DV%INSTANT_VALUE < CF%SETPOINT(1) .AND. (CF%CURRENT_STATE .NEQV. CF%INITIAL_STATE)) THEN
             STATE2 = .FALSE.
          ELSEIF(DV%INSTANT_VALUE >= CF%SETPOINT(1) .AND. (CF%CURRENT_STATE .NEQV. CF%INITIAL_STATE)) THEN
             STATE2 = .TRUE.
          ENDIF
       ELSE
          IF (DV%INSTANT_VALUE < CF%SETPOINT(1) .AND. (CF%CURRENT_STATE .EQV. CF%INITIAL_STATE)) THEN
             STATE2 = .TRUE.
          ELSEIF(DV%INSTANT_VALUE > CF%SETPOINT(2) .AND. (CF%CURRENT_STATE .NEQV. CF%INITIAL_STATE)) THEN
             STATE2 = .FALSE.
          ELSEIF(DV%INSTANT_VALUE <= CF%SETPOINT(2) .AND. (CF%CURRENT_STATE .NEQV. CF%INITIAL_STATE)) THEN
             STATE2 = .TRUE.
          ENDIF
       ENDIF

   CASE (TIME_DELAY)
      SELECT CASE (CF%INPUT_TYPE(1))
         CASE (DEVICE_INPUT)
            DV => DEVICE(CF%INPUT(1))
            CF%MESH = DV%MESH
            IF (T(DV%MESH) - DV%T_CHANGE >= CF%DELAY) THEN
               T_CHANGE = T(DV%MESH)
               STATE2 = .TRUE.
            ENDIF
         CASE (CONTROL_INPUT)
            CF%MESH=CONTROL(CF%INPUT(1))%MESH
            IF (.NOT. CONTROL(CF%INPUT(1))%UPDATED) CALL EVALUATE_CONTROL(T,CF%INPUT(1))
            IF (T(CONTROL(CF%INPUT(1))%MESH)  - CONTROL(CF%INPUT(1))%T_CHANGE >= CF%DELAY) THEN
               IF (T(CONTROL(CF%INPUT(1))%MESH) > T_CHANGE) THEN
                  T_CHANGE = T(CONTROL(CF%INPUT(1))%MESH) 
               ENDIF
               STATE2 = .TRUE.
            ENDIF
      END SELECT

   CASE (CYCLING)

   CASE (CUSTOM)
      STATE2 = .FALSE.
      DV => DEVICE(CF%INPUT(1))
      CF%MESH = DV%MESH
      RAMP_INPUT = DV%INSTANT_VALUE
      RAMP_VALUE = EVALUATE_RAMP(RAMP_INPUT,0._EB,CF%RAMP_INDEX)
      IF (RAMP_VALUE > 0._EB) STATE2 = .TRUE.
      T_CHANGE = T(DV%MESH)
      
   CASE (KILL)
      SELECT CASE (CF%INPUT_TYPE(1))
         CASE (DEVICE_INPUT)
            DV => DEVICE(CF%INPUT(1))
            CF%MESH = DV%MESH
            IF (T(DV%MESH) >T_CHANGE) THEN
               T_CHANGE = T(DV%MESH)
            ENDIF
            STATE2 = DV%CURRENT_STATE               
         CASE (CONTROL_INPUT)
            IF (.NOT. CONTROL(CF%INPUT(1))%UPDATED) CALL EVALUATE_CONTROL(T,CF%INPUT(1)) 
            STATE2 = CONTROL(CF%INPUT(1))%CURRENT_STATE
            CF%MESH=CONTROL(CF%INPUT(1))%MESH
            IF (T(CONTROL(CF%INPUT(1))%MESH) > T_CHANGE) THEN
               T_CHANGE = T(CONTROL(CF%INPUT(1))%MESH) 
            ENDIF
      END SELECT
      IF (STATE2) PROCESS_STOP_STATUS=USER_STOP

   CASE (CORE_DUMP)
      SELECT CASE (CF%INPUT_TYPE(1))
         CASE (DEVICE_INPUT)
            DV => DEVICE(CF%INPUT(1))
            CF%MESH = DV%MESH
            IF (T(DV%MESH) >T_CHANGE) THEN
               T_CHANGE = T(DV%MESH)
            ENDIF
            STATE2 = DV%CURRENT_STATE               
         CASE (CONTROL_INPUT)
            IF (.NOT. CONTROL(CF%INPUT(1))%UPDATED) CALL EVALUATE_CONTROL(T,CF%INPUT(1)) 
            STATE2 = CONTROL(CF%INPUT(1))%CURRENT_STATE
            CF%MESH=CONTROL(CF%INPUT(1))%MESH
            IF (T(CONTROL(CF%INPUT(1))%MESH) > T_CHANGE) THEN
               T_CHANGE = T(CONTROL(CF%INPUT(1))%MESH) 
            ENDIF
      END SELECT
      IF (STATE2) CORE_CLOCK = T_CHANGE

END SELECT CONTROL_SELECT

IF (STATE2) THEN
   CF%CURRENT_STATE = .NOT. CF%INITIAL_STATE
ELSE
   CF%CURRENT_STATE = CF%INITIAL_STATE      
ENDIF

IF(CF%CURRENT_STATE .NEQV. CF%PRIOR_STATE) THEN
   CF%T_CHANGE = T_CHANGE
ENDIF

CF%UPDATED = .TRUE.

END SUBROUTINE EVALUATE_CONTROL

SUBROUTINE GET_REV_ctrl(MODULE_REV,MODULE_DATE)
INTEGER,INTENT(INOUT) :: MODULE_REV
CHARACTER(255),INTENT(INOUT) :: MODULE_DATE

WRITE(MODULE_DATE,'(A)') ctrlrev(INDEX(ctrlrev,':')+1:LEN_TRIM(ctrlrev)-2)
READ (MODULE_DATE,'(I5)') MODULE_REV
WRITE(MODULE_DATE,'(A)') ctrldate

END SUBROUTINE GET_REV_ctrl
END MODULE CONTROL_FUNCTIONS

 
