import {
  getAuth,
  signInAnonymously as firebaseSignInAnonymously,
  onAuthStateChanged as firebaseOnAuthStateChanged,
} from '@react-native-firebase/auth';
import {
  getFirestore,
  collection,
  doc,
  setDoc,
  getDoc,
  getDocs,
  addDoc,
  query,
  where,
  orderBy,
  Timestamp,
} from '@react-native-firebase/firestore';
import {getStorage, ref, uploadString, getDownloadURL} from '@react-native-firebase/storage';
import storage from '@react-native-firebase/storage';
import {UserProfile, Measurement} from '../types';

const auth = getAuth();
const db = getFirestore();

// Anonymous authentication
export const signInAnonymously = async (): Promise<string> => {
  try {
    const userCredential = await firebaseSignInAnonymously(auth);
    return userCredential.user.uid;
  } catch (error) {
    console.error('Anonymous sign in error:', error);
    throw error;
  }
};

export const getCurrentUser = () => {
  return auth.currentUser;
};

export const onAuthStateChanged = (callback: (user: any) => void) => {
  return firebaseOnAuthStateChanged(auth, callback);
};

// User Profile
export const saveUserProfile = async (
  uid: string,
  profile: UserProfile,
): Promise<void> => {
  try {
    const profileRef = doc(db, 'users', uid, 'profile', 'info');
    await setDoc(profileRef, {
      ...profile,
      surgeryDate: Timestamp.fromDate(profile.surgeryDate),
      createdAt: Timestamp.fromDate(profile.createdAt),
    });
  } catch (error) {
    console.error('Save profile error:', error);
    throw error;
  }
};

export const getUserProfile = async (
  uid: string,
): Promise<UserProfile | null> => {
  try {
    const profileRef = doc(db, 'users', uid, 'profile', 'info');
    const docSnap = await getDoc(profileRef);

    if (!docSnap.exists()) {
      return null;
    }

    const data = docSnap.data();
    return {
      name: data?.name || '',
      surgeryDate: data?.surgeryDate?.toDate() || new Date(),
      createdAt: data?.createdAt?.toDate() || new Date(),
    };
  } catch (error) {
    console.error('Get profile error:', error);
    throw error;
  }
};

// Measurements
export const saveMeasurement = async (
  uid: string,
  measurement: Omit<Measurement, 'id'>,
): Promise<string> => {
  try {
    const measurementsRef = collection(db, 'users', uid, 'measurements');
    const docRef = await addDoc(measurementsRef, {
      ...measurement,
      timestamp: Timestamp.fromDate(measurement.timestamp),
    });
    return docRef.id;
  } catch (error) {
    console.error('Save measurement error:', error);
    throw error;
  }
};

export const getMeasurements = async (uid: string): Promise<Measurement[]> => {
  try {
    const measurementsRef = collection(db, 'users', uid, 'measurements');
    const q = query(measurementsRef, orderBy('timestamp', 'desc'));
    const snapshot = await getDocs(q);

    return snapshot.docs.map(docSnap => ({
      id: docSnap.id,
      type: docSnap.data().type,
      angle: docSnap.data().angle,
      timestamp: docSnap.data().timestamp.toDate(),
      weekPostOp: docSnap.data().weekPostOp,
      photoUrl: docSnap.data().photoUrl,
    }));
  } catch (error) {
    console.error('Get measurements error:', error);
    throw error;
  }
};

export const getMeasurementsByType = async (
  uid: string,
  type: 'extension' | 'flexion',
): Promise<Measurement[]> => {
  try {
    const measurementsRef = collection(db, 'users', uid, 'measurements');
    const q = query(
      measurementsRef,
      where('type', '==', type),
      orderBy('timestamp', 'desc'),
    );
    const snapshot = await getDocs(q);

    return snapshot.docs.map(docSnap => ({
      id: docSnap.id,
      type: docSnap.data().type,
      angle: docSnap.data().angle,
      timestamp: docSnap.data().timestamp.toDate(),
      weekPostOp: docSnap.data().weekPostOp,
      photoUrl: docSnap.data().photoUrl,
    }));
  } catch (error) {
    console.error('Get measurements by type error:', error);
    throw error;
  }
};

// Photo Storage - using legacy API for file uploads as modular doesn't support putFile yet
export const uploadPhoto = async (
  uid: string,
  measurementId: string,
  localUri: string,
): Promise<string> => {
  try {
    const reference = storage().ref(`users/${uid}/photos/${measurementId}.jpg`);
    await reference.putFile(localUri);
    const downloadUrl = await reference.getDownloadURL();
    return downloadUrl;
  } catch (error) {
    console.error('Upload photo error:', error);
    throw error;
  }
};

// Helper functions
export const calculateWeekPostOp = (surgeryDate: Date): number => {
  const now = new Date();
  const diffTime = Math.abs(now.getTime() - surgeryDate.getTime());
  const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));
  return Math.floor(diffDays / 7);
};
