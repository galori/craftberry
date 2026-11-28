export type AppAttestErrorCode =
  | 'malformed_object'
  | 'unsupported_format'
  | 'invalid_certificate_chain'
  | 'invalid_challenge'
  | 'invalid_key_identifier'
  | 'invalid_app_identifier'
  | 'invalid_authenticator_flags'
  | 'invalid_environment'
  | 'invalid_counter'
  | 'invalid_extensions'
  | 'missing_receipt'
  | 'invalid_receipt'
  | 'invalid_assertion_signature'
  | 'invalid_assertion_app_identifier'
  | 'invalid_assertion_counter'
  | 'invalid_assertion_extensions';

export class AppAttestError extends Error {
  readonly code: AppAttestErrorCode;
  constructor(code: AppAttestErrorCode, message?: string) {
    super(message ?? code);
    this.name = 'AppAttestError';
    this.code = code;
  }
}
