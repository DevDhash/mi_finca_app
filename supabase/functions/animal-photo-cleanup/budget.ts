/** Checks are synchronous and must not start work. The caller owns the clock.
 * A future adapter must also bound in-flight I/O; these checks cannot cancel it.
 * canFinish means remaining time, not permission to ACK or a valid SQL lease.
 */
export interface CleanupBudget {
  canStartList(): boolean;
  canStartRemove(): boolean;
  canFinish(): boolean;
}
