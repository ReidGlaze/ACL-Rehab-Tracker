export interface UserProfile {
  name: string;
  surgeryDate: Date;
  createdAt: Date;
}

export interface Measurement {
  id: string;
  type: 'extension' | 'flexion';
  angle: number;
  timestamp: Date;
  weekPostOp: number;
  photoUrl: string;
}

export interface Keypoint {
  x: number;
  y: number;
  confidence: number;
}

export interface PoseResult {
  hip: Keypoint;
  knee: Keypoint;
  ankle: Keypoint;
  angle: number;
}

export type RootStackParamList = {
  Onboarding: undefined;
  Welcome: undefined;
  NameInput: undefined;
  SurgeryDate: undefined;
  Main: undefined;
};

export type MainTabParamList = {
  Home: undefined;
  Measure: undefined;
  History: undefined;
  Progress: undefined;
};

export type MeasureStackParamList = {
  Camera: undefined;
  Result: {
    photoUri: string;
    poseResult: PoseResult;
    measurementType: 'extension' | 'flexion';
  };
};
