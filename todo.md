# Modularity and Maintainability Improvements

## Bug Fixes [✓]
- [x] Add missing stopSpeaking method to VoiceService
- [x] Add missing finishSpeaking method to VoiceService
- [x] Fix variable name inconsistencies (_currentBuffer -> _currentTtsBuffer)
- [x] Fix TTS completion callback timing (mic activating too early)

## 1. Service Interfaces [✓]
- [x] Create `base_llm_service.dart` with abstract base class
- [x] Create `base_tts_service.dart` with abstract base class
- [x] Refactor DeepSeek service to implement base LLM interface
- [x] Refactor OpenRouter service to implement base LLM interface
- [x] Refactor Voice service to use base TTS interface

## 2. Provider Factory Pattern [✓]
- [x] Create `llm_service_factory.dart`
- [x] Create `tts_service_factory.dart`
- [x] Implement factory methods for existing services
- [x] Update ChatProvider to use factories

## 3. Configuration Management [ ]
- [ ] Create `llm_config.dart` for LLM provider settings
- [ ] Create `tts_config.dart` for TTS provider settings
- [ ] Implement configuration registry
- [ ] Update settings screen to use new config classes

## 4. Error Handling [ ]
- [ ] Create service-specific error types
- [ ] Implement centralized error handling system
- [ ] Add error recovery mechanisms
- [ ] Update services to use new error system

## 5. Testing Infrastructure [ ]
- [ ] Create mock LLM service implementation
- [ ] Create mock TTS service implementation
- [ ] Add test utilities and helpers
- [ ] Implement integration tests

## Progress Tracking
- Each section will be marked complete [✓] when all its subtasks are done
- Individual tasks will be marked with [x] when completed